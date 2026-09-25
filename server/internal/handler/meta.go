package handler

import (
	"net/http"
	"strconv"

	"driftclip/server/internal/middleware"
)

// ServerVersion 服务端版本号，随发布更新（ROADMAP P3.3）。
const ServerVersion = "0.1.1"

// GET /api/v1/meta：公开端点，返回服务端版本与账户级上限。
// 客户端在连接校验时读取：单条正文预校验改用服务端实际上限；
// 版本号供后续兼容性检查与排查使用。
func (s *Server) meta(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"version":                  ServerVersion,
		"max_history_records":      s.Store.MaxHistoryRecords,
		"max_clipboard_text_bytes": s.MaxClipboardTextBytes,
	})
}

// uploadRateKey 上传限流键：鉴权后的 account_id（ROADMAP P3.1）。
func (s *Server) uploadRateKey(r *http.Request) string {
	return strconv.FormatInt(middleware.AccountID(r.Context()), 10)
}
