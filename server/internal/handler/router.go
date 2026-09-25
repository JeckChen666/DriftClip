package handler

import (
	"net/http"

	"driftclip/server/internal/middleware"
)

// Routes 装配全部 API 路由与中间件。
//
// 中间件顺序（外层→内层）：请求日志 → HTTPS 检查 → CSRF → 路由级鉴权。
// 路由级鉴权按权限边界挂载（Spec §7.2）：
//   - 公开：注册、登录；
//   - 会话：登出、改密、me、Key 生成/重置；
//   - Key：历史上传；
//   - 会话或 Key 任一种：历史查看/详情/删除/批量删除/清空。
func (s *Server) Routes() http.Handler {
	deps := middleware.Deps{Store: s.Store, KeyPepper: s.KeyPepper}

	mux := http.NewServeMux()
	mux.Handle("POST /api/v1/auth/register", http.HandlerFunc(s.register))
	mux.Handle("POST /api/v1/auth/login", http.HandlerFunc(s.login))
	mux.Handle("POST /api/v1/auth/logout", middleware.RequireSession(deps)(http.HandlerFunc(s.logout)))
	mux.Handle("POST /api/v1/auth/change-password", middleware.RequireSession(deps)(http.HandlerFunc(s.changePassword)))
	mux.Handle("GET /api/v1/auth/me", middleware.RequireSession(deps)(http.HandlerFunc(s.me)))
	mux.Handle("GET /api/v1/keys", middleware.RequireSession(deps)(http.HandlerFunc(s.keyStatus)))
	mux.Handle("GET /api/v1/keys/secret", middleware.RequireSession(deps)(http.HandlerFunc(s.revealKey)))
	mux.Handle("POST /api/v1/keys", middleware.RequireSession(deps)(http.HandlerFunc(s.generateKey)))
	mux.Handle("POST /api/v1/keys/reset", middleware.RequireSession(deps)(http.HandlerFunc(s.resetKey)))
	mux.Handle("GET /api/v1/history", middleware.RequireAnyAuth(deps)(http.HandlerFunc(s.list)))
	mux.Handle("GET /api/v1/history/{id}", middleware.RequireAnyAuth(deps)(http.HandlerFunc(s.get)))
	mux.Handle("POST /api/v1/history", middleware.RequireKey(deps)(http.HandlerFunc(s.upload)))
	mux.Handle("DELETE /api/v1/history/{id}", middleware.RequireAnyAuth(deps)(http.HandlerFunc(s.delete)))
	mux.Handle("POST /api/v1/history/batch-delete", middleware.RequireAnyAuth(deps)(http.HandlerFunc(s.batchDelete)))
	mux.Handle("POST /api/v1/history/clear", middleware.RequireAnyAuth(deps)(http.HandlerFunc(s.clear)))

	var h http.Handler = mux
	h = middleware.RequestLogging(h)
	h = middleware.HTTPS(s.RequireHTTPS, s.TrustedNets)(h)
	// 注册/登录为公开端点，豁免 CSRF（评审 F3）
	h = middleware.CSRF("/api/v1/auth/register", "/api/v1/auth/login")(h)
	return h
}
