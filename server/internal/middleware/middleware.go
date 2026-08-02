// Package middleware 提供 HTTP 中间件：请求日志、HTTPS 检查、CSRF 防护、
// 以及 Web 会话 / 原生 Key 两种鉴权。
//
// 权限边界（见 Spec）：
//   - 会话鉴权：Web 用户，凭 Cookie 会话；
//   - Key 鉴权：原生客户端，凭 Authorization: Bearer <Key>；
//   - 两种凭据都能获得 account_id，处理器统一按账户作用域读写。
package middleware

import (
	"context"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"driftclip/server/internal/auth"
	"driftclip/server/internal/store"
)

// SessionCookieName 是 Web 会话 Cookie 的名称。
const SessionCookieName = "driftclip_session"

// Deps 承载鉴权中间件所需的外部依赖。
type Deps struct {
	Store     *store.Store
	KeyPepper string // 用于 Key 哈希，与 auth.HashKey 一致
}

type ctxKey int

const (
	ctxAccountID ctxKey = iota
	ctxAuthMethod
)

// AccountID 从请求上下文取当前账户 ID（未鉴权时为 0）。
func AccountID(ctx context.Context) int64 {
	id, _ := ctx.Value(ctxAccountID).(int64)
	return id
}

// AuthMethod 返回当前请求的鉴权方式："session" 或 "key"。
func AuthMethod(ctx context.Context) string {
	m, _ := ctx.Value(ctxAuthMethod).(string)
	return m
}

// SetSessionCookie 写 Web 会话 Cookie：Secure、HttpOnly、SameSite=Lax。
// secure 为 true 时（生产 HTTPS）附加 Secure 标记。
func SetSessionCookie(w http.ResponseWriter, token string, maxAge time.Duration, secure bool) {
	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookieName,
		Value:    token,
		Path:     "/",
		MaxAge:   int(maxAge.Seconds()),
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteLaxMode,
	})
}

// ClearSessionCookie 清除会话 Cookie（退出登录）。
func ClearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

// RequestLogging 记录每个请求的方法、路径、状态码与耗时。
// 不记录任何凭据或正文（Spec：Key/密码/会话/正文不得入日志）。
func RequestLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		slog.Info("http_request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"dur_ms", time.Since(start).Milliseconds(),
		)
	})
}

// HTTPS 检查中间件。开启时拒绝非 HTTPS 请求：
//   - 直连 TLS（r.TLS != nil）视为安全；
//   - 仅当请求来自配置的可信代理（RemoteAddr ∈ trustedNets）时，才接受其
//     X-Forwarded-Proto: https 转发头。
//
// 与 clientIP 的信任模型保持一致：不信任任意来源构造的转发头（评审 F1）。
// 本地开发由配置 require_https=false 关闭（Spec：部署层强制 HTTPS，应用可配置执行）。
func HTTPS(enabled bool, trustedNets []*net.IPNet) func(http.Handler) http.Handler {
	if !enabled {
		return func(next http.Handler) http.Handler { return next }
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			secure := r.TLS != nil
			if !secure && ipInNets(remoteIP(r), trustedNets) && r.Header.Get("X-Forwarded-Proto") == "https" {
				secure = true
			}
			if !secure {
				WriteError(w, http.StatusBadRequest, "仅允许 HTTPS 请求")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// CSRF 防护：对所有状态修改方法（非 GET/HEAD/OPTIONS），若请求携带会话 Cookie
// 则必须带 X-Requested-With: XMLHttpRequest 头。Key 请求不携带会话 Cookie，不受影响。
// 配合 SameSite=Lax，构成对跨站请求伪造的双重防护。
// exemptPaths 豁免公开路由（注册/登录）：这些端点本就无会话保护，
// 持有旧会话 Cookie 的浏览器请求不应被误拦（评审 F3）。
func CSRF(exemptPaths ...string) func(http.Handler) http.Handler {
	exempt := make(map[string]bool, len(exemptPaths))
	for _, p := range exemptPaths {
		exempt[p] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			switch r.Method {
			case http.MethodGet, http.MethodHead, http.MethodOptions:
				next.ServeHTTP(w, r)
				return
			}
			if exempt[r.URL.Path] {
				next.ServeHTTP(w, r)
				return
			}
			if _, err := r.Cookie(SessionCookieName); err == nil {
				if r.Header.Get("X-Requested-With") != "XMLHttpRequest" {
					WriteError(w, http.StatusForbidden, "CSRF 校验失败")
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// remoteIP 提取直连地址的 IP。
func remoteIP(r *http.Request) net.IP {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	return net.ParseIP(host)
}

func ipInNets(ip net.IP, nets []*net.IPNet) bool {
	if ip == nil {
		return false
	}
	for _, n := range nets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// RequireSession 要求 Web 会话鉴权，把账户 ID 放入上下文。
// 无 Cookie、会话已过期或 token 无效时返回 401。
func RequireSession(d Deps) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			accountID, ok := resolveSession(d, r)
			if !ok {
				WriteError(w, http.StatusUnauthorized, "未登录或会话已失效")
				return
			}
			ctx := context.WithValue(r.Context(), ctxAccountID, accountID)
			ctx = context.WithValue(ctx, ctxAuthMethod, "session")
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireKey 要求原生 Key 鉴权（Authorization: Bearer <Key>），把账户 ID 放入上下文。
// Key 缺失、无效或已重置时返回 401。
func RequireKey(d Deps) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			accountID, ok := resolveKey(d, r)
			if !ok {
				WriteError(w, http.StatusUnauthorized, "Key 无效或已被重置")
				return
			}
			ctx := context.WithValue(r.Context(), ctxAccountID, accountID)
			ctx = context.WithValue(ctx, ctxAuthMethod, "key")
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireAnyAuth 接受会话或 Key 任一种有效凭据（查看/删除类接口）。
func RequireAnyAuth(d Deps) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			accountID, ok := resolveSession(d, r)
			method := "session"
			if !ok {
				accountID, ok = resolveKey(d, r)
				method = "key"
			}
			if !ok {
				WriteError(w, http.StatusUnauthorized, "未登录或 Key 无效")
				return
			}
			ctx := context.WithValue(r.Context(), ctxAccountID, accountID)
			ctx = context.WithValue(ctx, ctxAuthMethod, method)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func resolveSession(d Deps, r *http.Request) (int64, bool) {
	cookie, err := r.Cookie(SessionCookieName)
	if err != nil {
		return 0, false
	}
	tokenHash := auth.HashSessionToken(cookie.Value)
	sess, err := d.Store.GetSessionByTokenHash(r.Context(), tokenHash)
	if err != nil || sess == nil {
		return 0, false
	}
	return sess.AccountID, true
}

func resolveKey(d Deps, r *http.Request) (int64, bool) {
	authz := r.Header.Get("Authorization")
	if !strings.HasPrefix(authz, "Bearer ") {
		return 0, false
	}
	key := strings.TrimSpace(strings.TrimPrefix(authz, "Bearer "))
	if key == "" {
		return 0, false
	}
	keyHash := auth.HashKey(key, d.KeyPepper)
	accountID, err := d.Store.GetAccountIDByKeyHash(r.Context(), keyHash)
	if err != nil || accountID == 0 {
		return 0, false
	}
	return accountID, true
}

// WriteError 输出统一 JSON 错误体 {"error": "<信息>"}。错误信息不泄漏内部细节。
func WriteError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (sw *statusWriter) WriteHeader(code int) {
	sw.status = code
	sw.ResponseWriter.WriteHeader(code)
}
