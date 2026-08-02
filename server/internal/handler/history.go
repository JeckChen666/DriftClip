package handler

import (
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"driftclip/server/internal/middleware"
	"driftclip/server/internal/store"
)

var allowedPlatforms = map[string]bool{
	"windows": true, "macos": true, "linux": true, "android": true, "ios": true,
}

var allowedSources = map[string]bool{"clipboard": true, "manual": true}

type uploadRequest struct {
	Content        string `json:"content"`
	Source         string `json:"source"`
	Platform       string `json:"platform"`
	OSVersion      string `json:"os_version,omitempty"`
	DeviceModel    string `json:"device_model,omitempty"`
	AppVersion     string `json:"app_version,omitempty"`
	InstallationID string `json:"installation_id,omitempty"`
}

type historyListResponse struct {
	Items    []map[string]any `json:"items"`
	Total    int              `json:"total"`
	Page     int              `json:"page"`
	PageSize int              `json:"page_size"`
}

// upload POST /api/v1/history  （仅原生 Key 鉴权）
// 上传一条纯文本记录。服务端校验正文非空、UTF-8、不超过上限，写入 received_at 并执行保留策略。
func (s *Server) upload(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	var req uploadRequest
	if err := readJSON(r, w, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	// 空正文拒绝（验收 10）
	if req.Content == "" {
		middleware.WriteError(w, http.StatusBadRequest, "正文不能为空")
		return
	}
	// 超限正文拒绝，不静默截断（Spec §3.2）
	if int64(len([]byte(req.Content))) > s.MaxClipboardTextBytes {
		middleware.WriteError(w, http.StatusRequestEntityTooLarge, "正文超过大小上限")
		return
	}
	// 仅接收 UTF-8 纯文本
	if !utf8.ValidString(req.Content) {
		middleware.WriteError(w, http.StatusBadRequest, "正文必须是合法 UTF-8 文本")
		return
	}
	if !allowedSources[req.Source] {
		middleware.WriteError(w, http.StatusBadRequest, "source 必须是 clipboard 或 manual")
		return
	}
	// 手动输入去除首尾空格后为空时不允许提交（Spec §3.2，评审 F4）
	if req.Source == "manual" && strings.TrimSpace(req.Content) == "" {
		middleware.WriteError(w, http.StatusBadRequest, "正文不能为空")
		return
	}
	if !allowedPlatforms[req.Platform] {
		middleware.WriteError(w, http.StatusBadRequest, "platform 无效")
		return
	}
	rec, err := s.Store.CreateHistory(r.Context(), accountID, store.NewHistory{
		Content:        req.Content,
		Source:         req.Source,
		PublicIP:       s.clientIP(r),
		Platform:       req.Platform,
		OSVersion:      req.OSVersion,
		DeviceModel:    req.DeviceModel,
		AppVersion:     req.AppVersion,
		InstallationID: req.InstallationID,
	})
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"id":          rec.ID,
		"received_at": s.formatTZ(rec.ReceivedAt),
	})
}

// list GET /api/v1/history  （会话或 Key 鉴权）
// 列表默认按 received_at 倒序分页；支持 platform / q（正文子串，忽略英文字母大小写）/
// from / to（UTC+8 时间范围）组合筛选，条件 AND 关系。
// 列表投影：正文仅返回前 500 字符预览，不返回完整正文与完整 IP（详情接口才返回）。
func (s *Server) list(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	q := r.URL.Query()

	page, err := parsePositiveInt(q.Get("page"), 1)
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "page 参数无效")
		return
	}
	// 限制 page 上限，避免 (page-1)*pageSize 溢出为负 offset（评审 F7）
	if page > 10_000_000 {
		middleware.WriteError(w, http.StatusBadRequest, "page 参数无效")
		return
	}
	pageSize, err := parsePositiveInt(q.Get("page_size"), 20)
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "page_size 参数无效")
		return
	}
	if pageSize > 100 {
		pageSize = 100
	}

	from, err := s.parseTimeParam(q.Get("from"))
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "from 时间格式无效")
		return
	}
	to, err := s.parseTimeParam(q.Get("to"))
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "to 时间格式无效")
		return
	}

	f := store.ListFilter{
		Platform: q.Get("platform"),
		Query:    q.Get("q"),
		From:     from,
		To:       to,
		Limit:    pageSize,
		Offset:   (page - 1) * pageSize,
	}
	if f.Platform != "" && !allowedPlatforms[f.Platform] {
		middleware.WriteError(w, http.StatusBadRequest, "platform 无效")
		return
	}

	items, err := s.Store.ListHistory(r.Context(), accountID, f)
	if err != nil {
		s.internalError(w, err)
		return
	}
	total, err := s.Store.CountHistory(r.Context(), accountID, f)
	if err != nil {
		s.internalError(w, err)
		return
	}

	out := historyListResponse{Items: make([]map[string]any, 0, len(items)), Total: total, Page: page, PageSize: pageSize}
	for _, it := range items {
		out.Items = append(out.Items, map[string]any{
			"id":             it.ID,
			"content_preview": it.ContentPreview,
			"source":          it.Source,
			"received_at":     s.formatTZ(it.ReceivedAt),
			"platform":        it.Platform,
			"os_version":      it.OSVersion,
			"device_model":    it.DeviceModel,
			"app_version":     it.AppVersion,
			"installation_id": it.InstallationID,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

// get GET /api/v1/history/{id}  （会话或 Key 鉴权）
// 详情返回完整正文与完整公网 IP。非本人记录一律 404（不泄漏存在性，Spec §7.2）。
func (s *Server) get(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "记录 ID 无效")
		return
	}
	rec, err := s.Store.GetHistory(r.Context(), accountID, id)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if rec == nil {
		middleware.WriteError(w, http.StatusNotFound, "记录不存在")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"id":             rec.ID,
		"content":        rec.Content,
		"source":         rec.Source,
		"received_at":    s.formatTZ(rec.ReceivedAt),
		"public_ip":      rec.PublicIP,
		"platform":       rec.Platform,
		"os_version":     rec.OSVersion,
		"device_model":   rec.DeviceModel,
		"app_version":    rec.AppVersion,
		"installation_id": rec.InstallationID,
	})
}

// delete DELETE /api/v1/history/{id}  （会话或 Key 鉴权）
func (s *Server) delete(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "记录 ID 无效")
		return
	}
	ok, err := s.Store.DeleteHistory(r.Context(), accountID, id)
	if err != nil {
		s.internalError(w, err)
		return
	}
	if !ok {
		middleware.WriteError(w, http.StatusNotFound, "记录不存在")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type batchDeleteRequest struct {
	IDs []int64 `json:"ids"`
}

// batchDelete POST /api/v1/history/batch-delete  （会话或 Key 鉴权）
// 批量删除，仅作用于当前账户的记录，返回实际删除条数。
func (s *Server) batchDelete(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	var req batchDeleteRequest
	if err := readJSON(r, w, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	if len(req.IDs) == 0 {
		middleware.WriteError(w, http.StatusBadRequest, "ids 不能为空")
		return
	}
	deleted, err := s.Store.DeleteHistories(r.Context(), accountID, req.IDs)
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"deleted": deleted})
}

// clear POST /api/v1/history/clear  （会话或 Key 鉴权）
// 清空当前账户全部历史。5 秒倒计时由前端控制（Spec §6.2），服务端收到请求即执行。
func (s *Server) clear(w http.ResponseWriter, r *http.Request) {
	accountID := middleware.AccountID(r.Context())
	deleted, err := s.Store.ClearHistory(r.Context(), accountID)
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"deleted": deleted})
}

func parsePositiveInt(v string, def int) (int, error) {
	if v == "" {
		return def, nil
	}
	n, err := strconv.Atoi(strings.TrimSpace(v))
	if err != nil || n < 1 {
		return 0, &strconv.NumError{Func: "Atoi", Num: v, Err: strconv.ErrSyntax}
	}
	return n, nil
}
