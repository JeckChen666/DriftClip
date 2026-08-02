package handler

import (
	"errors"
	"net/http"

	"driftclip/server/internal/auth"
	"driftclip/server/internal/middleware"
	"driftclip/server/internal/store"
)

// keyStatus GET /api/v1/keys
// 返回账户是否已有有效 Key（Web 端渲染 Key 管理页所需，P02 发现的增量只读端点）。
func (s *Server) keyStatus(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	existing, err := s.Store.GetKeyHashByAccount(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"has_key": existing != ""})
}

// generateKey POST /api/v1/keys
// 生成初始 Key。账户已有 Key 时返回 409（需用重置接口更换，不允许静默覆盖）。
// 完整 Key 只在本次响应中返回一次，服务端只保存哈希（Spec §2.2）。
func (s *Server) generateKey(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	existing, err := s.Store.GetKeyHashByAccount(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if existing != "" {
		middleware.WriteError(w, http.StatusConflict, "已存在有效 Key，如需更换请使用重置")
		return
	}
	key, err := auth.GenerateKey()
	if err != nil {
		s.internalError(w, err)
		return
	}
	if err := s.Store.InsertKey(r.Context(), accountID, auth.HashKey(key, s.KeyPepper)); err != nil {
		if errors.Is(err, store.ErrKeyExists) {
			middleware.WriteError(w, http.StatusConflict, "已存在有效 Key，如需更换请使用重置")
			return
		}
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"key": key})
}

// resetKey POST /api/v1/keys/reset
// 重置 Key：新 Key 立即生效、旧 Key 立即且永久失效，历史数据保留（Spec §2.2）。
// 账户尚无 Key 时返回 409（与生成接口语义一致，重置针对已有 Key，评审 Q2）。
// 5 秒倒计时由前端控制，服务端收到请求即执行重置。完整 Key 只在本次响应中返回一次。
func (s *Server) resetKey(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	existing, err := s.Store.GetKeyHashByAccount(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if existing == "" {
		middleware.WriteError(w, http.StatusConflict, "账户尚无 Key，请先生成")
		return
	}
	key, err := auth.GenerateKey()
	if err != nil {
		s.internalError(w, err)
		return
	}
	if err := s.Store.ResetKey(r.Context(), accountID, auth.HashKey(key, s.KeyPepper)); err != nil {
		if errors.Is(err, store.ErrKeyExists) {
			// 并发重置时另一请求已先写入，仍返回该失败语义，客户端可重试。
			middleware.WriteError(w, http.StatusConflict, "重置冲突，请重试")
			return
		}
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"key": key})
}
