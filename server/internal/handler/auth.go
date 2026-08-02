package handler

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"driftclip/server/internal/auth"
	"driftclip/server/internal/middleware"
	"driftclip/server/internal/store"
)

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// validateEmail 仅做基础格式检查（非空、含 @、长度合理），不验证邮箱所有权（Spec §2.1）。
func validateEmail(email string) bool {
	if email == "" || len(email) > 254 {
		return false
	}
	if !strings.Contains(email, "@") {
		return false
	}
	_, rest, found := strings.Cut(email, "@")
	return found && rest != "" && !strings.ContainsAny(rest, " \t")
}

// register POST /api/v1/auth/register
// 创建账户并直接建立会话（注册即登录）。账户初始没有 Key。
func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if !s.RegistrationEnabled {
		middleware.WriteError(w, http.StatusForbidden, "注册已关闭")
		return
	}
	var req credentials
	if err := readJSON(r, w, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	email := normalizeEmail(req.Email)
	if !validateEmail(email) {
		middleware.WriteError(w, http.StatusBadRequest, "邮箱格式无效")
		return
	}
	if strings.TrimSpace(req.Password) == "" {
		middleware.WriteError(w, http.StatusBadRequest, "密码不能为空")
		return
	}
	passwordHash, err := auth.HashPassword(req.Password)
	if err != nil {
		s.internalError(w, err)
		return
	}
	acct, err := s.Store.CreateAccount(r.Context(), email, passwordHash)
	if err != nil {
		if errors.Is(err, store.ErrDuplicateEmail) {
			middleware.WriteError(w, http.StatusConflict, "该邮箱已注册")
			return
		}
		s.internalError(w, err)
		return
	}
	if err := s.createSession(w, r, acct.ID); err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"email": acct.Email})
}

// login POST /api/v1/auth/login
// 登录失败统一返回模糊错误，不区分"邮箱不存在"与"密码错误"（避免账户枚举）。
func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req credentials
	if err := readJSON(r, w, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	email := normalizeEmail(req.Email)
	acct, err := s.Store.GetAccountByEmail(r.Context(), email)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if acct == nil {
		middleware.WriteError(w, http.StatusUnauthorized, "邮箱或密码错误")
		return
	}
	ok, err := auth.VerifyPassword(req.Password, acct.PasswordHash)
	if err != nil || !ok {
		middleware.WriteError(w, http.StatusUnauthorized, "邮箱或密码错误")
		return
	}
	if err := s.createSession(w, r, acct.ID); err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"email": acct.Email})
}

// logout POST /api/v1/auth/logout
// 作废当前会话并清除 Cookie。
func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(middleware.SessionCookieName); err == nil {
		tokenHash := auth.HashSessionToken(cookie.Value)
		_ = s.Store.DeleteSession(r.Context(), tokenHash)
	}
	middleware.ClearSessionCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

// changePassword POST /api/v1/auth/change-password
// 必须输入当前密码；修改成功后所有 Web 会话立即失效（含当前会话，需重新登录）。
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	var req changePasswordRequest
	if err := readJSON(r, w, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	acct, err := s.Store.GetAccountByID(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if acct == nil {
		middleware.WriteError(w, http.StatusUnauthorized, "账户不存在")
		return
	}
	ok, err := auth.VerifyPassword(req.CurrentPassword, acct.PasswordHash)
	if err != nil || !ok {
		middleware.WriteError(w, http.StatusForbidden, "当前密码错误")
		return
	}
	if strings.TrimSpace(req.NewPassword) == "" {
		middleware.WriteError(w, http.StatusBadRequest, "新密码不能为空")
		return
	}
	newHash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		s.internalError(w, err)
		return
	}
	// 改密 + 作废全部会话在单事务内完成（Spec §2.3；评审 F5 保证原子性）
	if err := s.Store.ChangePasswordAndRevokeSessions(r.Context(), accountID, newHash); err != nil {
		s.internalError(w, err)
		return
	}
	middleware.ClearSessionCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

// me GET /api/v1/auth/me
// 返回当前登录账户邮箱，供前端判断登录态。
func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	acct, err := s.Store.GetAccountByID(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if acct == nil {
		middleware.WriteError(w, http.StatusUnauthorized, "账户不存在")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"email": acct.Email})
}

// createSession 生成会话 token，写库并设置 Cookie。
// secure 标记取自配置的 HTTPS 强制开关（生产开启时为 Cookie 加 Secure）。
func (s *Server) createSession(w http.ResponseWriter, r *http.Request, accountID int64) error {
	token, tokenHash, err := auth.NewSessionToken()
	if err != nil {
		return err
	}
	expires := time.Now().UTC().Add(s.SessionDuration)
	if err := s.Store.CreateSession(r.Context(), accountID, tokenHash, expires); err != nil {
		return err
	}
	middleware.SetSessionCookie(w, token, s.SessionDuration, s.SecureCookies)
	return nil
}

func (s *Server) internalError(w http.ResponseWriter, err error) {
	s.logError(err)
	middleware.WriteError(w, http.StatusInternalServerError, "服务器内部错误")
}
