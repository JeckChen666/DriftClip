// Package handler 实现 HTTP API 处理器与路由装配。
package handler

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"driftclip/server/internal/store"
)

// Server 聚合所有 handler 依赖。
type Server struct {
	Store                 *store.Store
	Location              *time.Location // 业务时区（Asia/Shanghai）
	SessionDuration       time.Duration  // 会话有效期
	SessionSecret         string
	KeyPepper             string
	RegistrationEnabled   bool
	MaxClipboardTextBytes int64
	TrustedNets           []*net.IPNet  // 可信反向代理 CIDR
	SecureCookies         bool          // 生产 HTTPS 开启时 Cookie 附加 Secure 标记
	RequireHTTPS          bool          // 强制 HTTPS（部署层由反向代理终止 TLS）
}

// logError 记录内部错误（不记录任何敏感内容，仅错误本身与调用上下文）。
func (s *Server) logError(err error) {
	slog.Error("internal_error", "err", err)
}

// formatTZ 把 UTC 时间按业务时区格式化为 RFC3339（如 2026-08-02T19:00:00+08:00）。
// 所有 API 时间展示统一走业务时区（Spec：业务时区固定 Asia/Shanghai）。
func (s *Server) formatTZ(t time.Time) string {
	return t.In(s.Location).Format(time.RFC3339)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v != nil {
		json.NewEncoder(w).Encode(v)
	}
}

// readJSON 读取并解码 JSON 请求体。限制请求体大小、拒绝未知字段与多余 JSON。
func readJSON(r *http.Request, w http.ResponseWriter, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return errors.New("请求体不是合法 JSON")
	}
	if dec.More() {
		return errors.New("请求体包含多余内容")
	}
	return nil
}

// normalizeEmail 按 Spec 规范化邮箱：去首尾空格、转小写。
func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// parseTimeParam 解析时间筛选参数：
//   - RFC3339（带时区）直接解析；
//   - 无时区的 "2006-01-02" / "2006-01-02 15:04:05" 按业务时区解释。
//
// 返回 RFC3339 UTC 字符串，用于与存储的 received_at 比较。
func (s *Server) parseTimeParam(v string) (string, error) {
	if v == "" {
		return "", nil
	}
	formats := []string{time.RFC3339, "2006-01-02T15:04:05", "2006-01-02 15:04:05", "2006-01-02"}
	for _, f := range formats {
		if t, err := time.ParseInLocation(f, v, s.Location); err == nil {
			return t.UTC().Format(time.RFC3339), nil
		}
	}
	return "", errors.New("时间格式无效")
}

// clientIP 获取服务端观测到的请求来源公网 IP。
// 仅当请求来自配置的可信代理时才信任 X-Forwarded-For/X-Real-IP 转发头；
// 否则使用直接连接地址。不接受客户端自行提交的 IP（Spec §7.3）。
func (s *Server) clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	if ip != nil && s.ipInTrusted(ip) {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			parts := strings.Split(xff, ",")
			return strings.TrimSpace(parts[0])
		}
		if xri := r.Header.Get("X-Real-IP"); xri != "" {
			return strings.TrimSpace(xri)
		}
	}
	return host
}

func (s *Server) ipInTrusted(ip net.IP) bool {
	for _, n := range s.TrustedNets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}
