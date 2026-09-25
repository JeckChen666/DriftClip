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
// 同时保存鉴权哈希与 AES-256-GCM 加密原文（Web 端可重复查看，Spec §2.2 修订）。
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
	cipher, nonce, err := auth.EncryptKey(key, s.KeyPepper)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if err := s.Store.InsertKey(r.Context(), accountID, auth.HashKey(key, s.KeyPepper), cipher, nonce); err != nil {
		if errors.Is(err, store.ErrKeyExists) {
			middleware.WriteError(w, http.StatusConflict, "已存在有效 Key，如需更换请使用重置")
			return
		}
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"key": key})
}

// revealKey GET /api/v1/keys/secret
// 返回当前生效 Key 的完整原文，供 Web 端随时查看与复制。
// 原文以 AES-256-GCM 加密保存（密钥由 key_pepper 域分离派生）；
// 旧版本生成的 Key 无加密副本，返回 409 提示重置。
func (s *Server) revealKey(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	cipher, nonce, hasKey, err := s.Store.GetKeySecretByAccount(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if !hasKey {
		middleware.WriteError(w, http.StatusNotFound, "账户尚无 Key，请先生成")
		return
	}
	if cipher == nil {
		middleware.WriteError(w, http.StatusConflict, "该 Key 生成于旧版本，无法回显；重置后即可随时查看")
		return
	}
	key, err := auth.DecryptKey(cipher, nonce, s.KeyPepper)
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"key": key})
}

// resetKey POST /api/v1/keys/reset
// 重置 Key：新 Key 立即生效、旧 Key 立即且永久失效，历史数据保留（Spec §2.2）。
// 账户尚无 Key 时返回 409（与生成接口语义一致，重置针对已有 Key，评审 Q2）。
// 5 秒倒计时由前端控制，服务端收到请求即执行重置。
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
	cipher, nonce, err := auth.EncryptKey(key, s.KeyPepper)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if err := s.Store.ResetKey(r.Context(), accountID, auth.HashKey(key, s.KeyPepper), cipher, nonce); err != nil {
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
