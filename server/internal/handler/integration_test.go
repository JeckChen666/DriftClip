package handler_test

// P01 服务端核心闭环集成测试。
//
// 覆盖 Spec 验收契约（V1 §10）的 API 级证据：
//   验收 1：同一账户多凭据可见同一批记录；
//   验收 2：账户严格隔离，跨账户一律拒绝；
//   验收 3：记录字段完整、IP 取自服务端观测；
//   验收 4：保留策略按服务端时间淘汰最旧；
//   验收 6：重置 Key 后旧 Key 立即失效、新 Key 可访问历史；
//   验收 10：无效 Key / 空正文 / 超限正文 / 非 HTTPS 被拒绝。
//
// 另覆盖：会话生命周期、Key 生命周期、CSRF、筛选、分页、IP 可信代理。

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"driftclip/server/internal/handler"
	"driftclip/server/internal/middleware"
	"driftclip/server/internal/store"
)

type testServer struct {
	h         http.Handler
	store     *store.Store
	closeFn   func()
	keyPepper string
}

type testOpts struct {
	maxRecords     int
	requireHTTPS   bool
	trustedProxies []string
	location       string // 业务时区名称，默认 UTC
}

func newTestServer(t *testing.T, opts testOpts) *testServer {
	t.Helper()
	if opts.maxRecords == 0 {
		opts.maxRecords = 100
	}
	loc := time.UTC
	if opts.location != "" {
		var err error
		loc, err = time.LoadLocation(opts.location)
		if err != nil {
			t.Fatalf("加载业务时区 %s: %v", opts.location, err)
		}
	}
	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "test.sqlite"), loc, opts.maxRecords)
	if err != nil {
		t.Fatalf("打开测试数据库: %v", err)
	}
	pepper := "test-pepper"
	var trusted []*net.IPNet
	for _, c := range opts.trustedProxies {
		_, ipn, _ := net.ParseCIDR(c)
		trusted = append(trusted, ipn)
	}
	s := &handler.Server{
		Store:                 st,
		Location:              loc,
		SessionDuration:       24 * time.Hour,
		KeyPepper:             pepper,
		RegistrationEnabled:   true,
		MaxClipboardTextBytes: 102400,
		TrustedNets:           trusted,
		RequireHTTPS:          opts.requireHTTPS,
		SecureCookies:         opts.requireHTTPS,
	}
	return &testServer{h: s.Routes(), store: st, closeFn: func() { st.Close() }, keyPepper: pepper}
}

func (ts *testServer) close() { ts.closeFn() }

// do 发送请求。headers 附加到请求（如 Cookie / Authorization / CSRF）。
func (ts *testServer) do(t *testing.T, method, path string, body any, headers map[string]string) *http.Response {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatalf("编码请求体: %v", err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	ts.h.ServeHTTP(rec, req)
	return rec.Result()
}

func decode(t *testing.T, res *http.Response, dst any) {
	t.Helper()
	defer res.Body.Close()
	if err := json.NewDecoder(res.Body).Decode(dst); err != nil {
		t.Fatalf("解码响应: %v", err)
	}
}

func sessionCookie(res *http.Response) string {
	for _, c := range res.Cookies() {
		if c.Name == middleware.SessionCookieName {
			return c.Value
		}
	}
	return ""
}

// registerAndLogin 注册并返回会话 Cookie。
func registerAndLogin(t *testing.T, ts *testServer, email string) string {
	t.Helper()
	res := ts.do(t, http.MethodPost, "/api/v1/auth/register", map[string]string{
		"email": email, "password": "pw123",
	}, nil)
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("注册失败: %d", res.StatusCode)
	}
	return sessionCookie(res)
}

// login 用已有账户登录并返回会话 Cookie。
func login(t *testing.T, ts *testServer, email, password string) string {
	t.Helper()
	res := ts.do(t, http.MethodPost, "/api/v1/auth/login", map[string]string{
		"email": email, "password": password,
	}, nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("登录失败: %d", res.StatusCode)
	}
	return sessionCookie(res)
}

// createKey 注册 + 生成 Key，返回完整 Key。
func createKey(t *testing.T, ts *testServer, email string) (cookie, key string) {
	t.Helper()
	cookie = registerAndLogin(t, ts, email)
	res := ts.do(t, http.MethodPost, "/api/v1/keys", nil, map[string]string{
		"Cookie":              "driftclip_session=" + cookie,
		"X-Requested-With":    "XMLHttpRequest",
	})
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("生成 Key 失败: %d", res.StatusCode)
	}
	var out map[string]string
	decode(t, res, &out)
	return cookie, out["key"]
}

// upload 用 Key 上传一条记录，返回 201。
func upload(t *testing.T, ts *testServer, key string, body map[string]any) *http.Response {
	t.Helper()
	return ts.do(t, http.MethodPost, "/api/v1/history", body, map[string]string{
		"Authorization": "Bearer " + key,
	})
}

func testBody(content, source, platform string) map[string]any {
	return map[string]any{
		"content": content, "source": source, "platform": platform,
		"os_version": "v1", "device_model": "TestBox", "app_version": "1.0.0",
		"installation_id": "install-uuid",
	}
}

// ---- 验收 1：同账户多凭据可见同一批记录 ----

func TestAccountSharedHistoryAcrossKeyAndSession(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")
	if key == "" {
		t.Fatal("Key 为空")
	}

	res := upload(t, ts, key, testBody("共享历史文本", "clipboard", "macos"))
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("上传失败: %d", res.StatusCode)
	}
	res.Body.Close()

	// 用 Key 列表可见
	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	var viaKey map[string]any
	decode(t, res, &viaKey)
	if viaKey["total"].(float64) != 1 {
		t.Fatalf("Key 列表应含 1 条，实际 %v", viaKey["total"])
	}

	// 用 Web 会话列表可见（验收 1）
	cookie := login(t, ts, "a@example.com", "pw123")
	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	var viaWeb map[string]any
	decode(t, res, &viaWeb)
	if viaWeb["total"].(float64) != 1 {
		t.Fatalf("Web 会话列表应含 1 条，实际 %v", viaWeb["total"])
	}
}

// ---- 验收 2：账户隔离 ----

func TestAccountIsolation(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	_, keyA := createKey(t, ts, "a@example.com")
	_, keyB := createKey(t, ts, "b@example.com")

	// A 上传
	res := upload(t, ts, keyA, testBody("A 的私有内容", "clipboard", "macos"))
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("A 上传失败: %d", res.StatusCode)
	}
	var up map[string]any
	decode(t, res, &up)
	recID := int64(up["id"].(float64))
	res.Body.Close()

	// B 用 Key 列表看不到 A 的记录
	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + keyB,
	})
	var viaB map[string]any
	decode(t, res, &viaB)
	if viaB["total"].(float64) != 0 {
		t.Fatalf("B 不应看到 A 的记录，实际 %v", viaB["total"])
	}

	// B 访问 A 的记录详情 → 404
	res = ts.do(t, http.MethodGet, "/api/v1/history/"+itoa(recID), nil, map[string]string{
		"Authorization": "Bearer " + keyB,
	})
	if res.StatusCode != http.StatusNotFound {
		t.Fatalf("B 访问 A 的详情应 404，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// B 删除 A 的记录 → 404
	res = ts.do(t, http.MethodDelete, "/api/v1/history/"+itoa(recID), nil, map[string]string{
		"Authorization": "Bearer " + keyB,
	})
	if res.StatusCode != http.StatusNotFound {
		t.Fatalf("B 删除 A 的记录应 404，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// A 的记录仍然存在
	res = ts.do(t, http.MethodGet, "/api/v1/history/"+itoa(recID), nil, map[string]string{
		"Authorization": "Bearer " + keyA,
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A 自己的详情应 200，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// B 上传自己的，A 看不到
	res = upload(t, ts, keyB, testBody("B 的内容", "manual", "windows"))
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("B 上传失败: %d", res.StatusCode)
	}
	res.Body.Close()
	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + keyA,
	})
	var viaA map[string]any
	decode(t, res, &viaA)
	if viaA["total"].(float64) != 1 {
		t.Fatalf("A 应只看到自己的 1 条，实际 %v", viaA["total"])
	}
}

// ---- 验收 3：记录字段完整、IP 取自服务端观测 ----

func TestRecordFieldsAndServerObservedIP(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")

	// 模拟从可信代理转发的请求：RemoteAddr 在可信网段，X-Forwarded-For 提供真实客户端 IP。
	req := httptest.NewRequest(http.MethodPost, "/api/v1/history",
		bytes.NewBufferString(`{"content":"带IP的记录","source":"clipboard","platform":"ios"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+key)
	req.RemoteAddr = "192.0.2.10:4000"
	// 注意：此用例使用未配置可信代理的 server，因此 IP 应为直连地址。
	rec := httptest.NewRecorder()
	ts.h.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("上传失败: %d", rec.Code)
	}
	var up map[string]any
	decode(t, rec.Result(), &up)
	id := int64(up["id"].(float64))

	// 详情返回完整字段与完整 IP
	res := ts.do(t, http.MethodGet, "/api/v1/history/"+itoa(id), nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	var detail map[string]any
	decode(t, res, &detail)
	if detail["content"] != "带IP的记录" {
		t.Fatalf("详情应返回完整正文，实际 %v", detail["content"])
	}
	if detail["public_ip"] != "192.0.2.10" {
		t.Fatalf("IP 应取直连地址，实际 %v", detail["public_ip"])
	}
	if detail["source"] != "clipboard" || detail["platform"] != "ios" {
		t.Fatalf("字段不完整: %v", detail)
	}
	if detail["received_at"] == nil || detail["installation_id"] == nil {
		t.Fatalf("时间/安装 ID 缺失: %v", detail)
	}
}

func TestTrustedProxyIP(t *testing.T) {
	ts := newTestServer(t, testOpts{trustedProxies: []string{"192.0.2.0/24"}})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")
	req := httptest.NewRequest(http.MethodPost, "/api/v1/history",
		bytes.NewBufferString(`{"content":"x","source":"manual","platform":"linux"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("X-Forwarded-For", "203.0.113.7, 10.0.0.1")
	req.RemoteAddr = "192.0.2.10:4000"
	rec := httptest.NewRecorder()
	ts.h.ServeHTTP(rec, req)
	var up map[string]any
	decode(t, rec.Result(), &up)
	id := int64(up["id"].(float64))

	res := ts.do(t, http.MethodGet, "/api/v1/history/"+itoa(id), nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	var detail map[string]any
	decode(t, res, &detail)
	if detail["public_ip"] != "203.0.113.7" {
		t.Fatalf("可信代理应取 X-Forwarded-For 首个地址，实际 %v", detail["public_ip"])
	}
}

// ---- 验收 4：保留策略 ----

func TestRetentionKeepsNewestN(t *testing.T) {
	ts := newTestServer(t, testOpts{maxRecords: 3})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")
	ids := make([]int64, 0, 5)
	for i := 0; i < 5; i++ {
		res := upload(t, ts, key, testBody("record-"+itoa(int64(i)), "manual", "macos"))
		if res.StatusCode != http.StatusCreated {
			t.Fatalf("上传 %d 失败: %d", i, res.StatusCode)
		}
		var up map[string]any
		decode(t, res, &up)
		ids = append(ids, int64(up["id"].(float64)))
	}

	// 只保留最新 3 条（id 3,4,5），最旧的 1,2 被淘汰
	res := ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	var out map[string]any
	decode(t, res, &out)
	if out["total"].(float64) != 3 {
		t.Fatalf("应保留 3 条，实际 %v", out["total"])
	}
	for _, removed := range []int64{ids[0], ids[1]} {
		r := ts.do(t, http.MethodGet, "/api/v1/history/"+itoa(removed), nil, map[string]string{
			"Authorization": "Bearer " + key,
		})
		if r.StatusCode != http.StatusNotFound {
			t.Fatalf("被淘汰的记录 %d 应 404，实际 %d", removed, r.StatusCode)
		}
		r.Body.Close()
	}
}

func TestStartupCleanupOnLoweredLimit(t *testing.T) {
	// 服务重启且上限调低时，启动阶段立即清理（Spec §3.4）
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "cleanup.sqlite")

	st, err := store.Open(path, time.UTC, 5)
	if err != nil {
		t.Fatal(err)
	}
	acct, err := st.CreateAccount(ctx, "c@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 5; i++ {
		if _, err := st.CreateHistory(ctx, acct.ID, store.NewHistory{
			Content: "x", Source: "manual", PublicIP: "1.1.1.1", Platform: "macos",
		}); err != nil {
			t.Fatal(err)
		}
	}
	st.Close()

	st2, err := store.Open(path, time.UTC, 2)
	if err != nil {
		t.Fatal(err)
	}
	defer st2.Close()
	n, err := st2.CleanupAccounts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if n != 3 {
		t.Fatalf("调低上限后应删除 3 条，实际 %d", n)
	}
	total, err := st2.CountHistory(ctx, acct.ID, store.ListFilter{})
	if err != nil {
		t.Fatal(err)
	}
	if total != 2 {
		t.Fatalf("应剩 2 条，实际 %d", total)
	}
}

// ---- 验收 6：重置 Key 后旧 Key 立即失效 ----

func TestKeyResetInvalidatesOldKey(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	cookie, oldKey := createKey(t, ts, "a@example.com")

	res := upload(t, ts, oldKey, testBody("重置前内容", "manual", "macos"))
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("旧 Key 上传失败: %d", res.StatusCode)
	}
	res.Body.Close()

	// 重置
	res = ts.do(t, http.MethodPost, "/api/v1/keys/reset", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("重置失败: %d", res.StatusCode)
	}
	var out map[string]string
	decode(t, res, &out)
	newKey := out["key"]
	if newKey == "" || newKey == oldKey {
		t.Fatal("重置应返回新 Key")
	}

	// 旧 Key 立即收到无效凭据响应（验收 6）
	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + oldKey,
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("旧 Key 应 401，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 新 Key 可访问原有历史（数据保留）
	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + newKey,
	})
	var out2 map[string]any
	decode(t, res, &out2)
	if out2["total"].(float64) != 1 {
		t.Fatalf("新 Key 应看到历史 1 条，实际 %v", out2["total"])
	}
}

// ---- 验收 10：无效 Key / 空正文 / 超限正文 / 非 HTTPS ----

func TestRejectedRequests(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")

	// 无效 Key → 401
	res := ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer dc_invalid_key",
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("无效 Key 应 401，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 空正文 → 400
	res = upload(t, ts, key, testBody("", "clipboard", "macos"))
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("空正文应 400，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 超限正文 → 413（默认上限 102400 字节）
	big := strings.Repeat("a", 102401)
	res = upload(t, ts, key, testBody(big, "clipboard", "macos"))
	if res.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("超限正文应 413，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 说明：Go 的 encoding/json 在解码字符串时会把非法 UTF-8 字节替换为 U+FFFD，
	// 因此"非 UTF-8 正文"无法通过 JSON API 触发；handler 中保留 utf8.ValidString
	// 作为纵深防御，但该路径不可测试。此条不属于 V1 §10 验收项，故不在此断言。

	// 未带凭据上传 → 401
	res = ts.do(t, http.MethodPost, "/api/v1/history", testBody("x", "clipboard", "macos"), nil)
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("未带凭据上传应 401，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

func TestRequireHTTPS(t *testing.T) {
	ts := newTestServer(t, testOpts{requireHTTPS: true})
	defer ts.close()

	// 明文 HTTP 请求被拒绝（验收 10）
	res := ts.do(t, http.MethodPost, "/api/v1/auth/login", map[string]string{
		"email": "a@example.com", "password": "x",
	}, nil)
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("明文请求应被拒，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

// ---- 会话生命周期 ----

func TestSessionLifecycle(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	cookie := registerAndLogin(t, ts, "a@example.com")

	// me 返回邮箱
	res := ts.do(t, http.MethodGet, "/api/v1/auth/me", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	var me map[string]string
	decode(t, res, &me)
	if me["email"] != "a@example.com" {
		t.Fatalf("me 邮箱错误: %v", me)
	}

	// 未登录访问 me → 401
	res = ts.do(t, http.MethodGet, "/api/v1/auth/me", nil, nil)
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("未登录应 401，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 登出
	res = ts.do(t, http.MethodPost, "/api/v1/auth/logout", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("登出失败: %d", res.StatusCode)
	}
	res.Body.Close()

	// 登出后会话失效
	res = ts.do(t, http.MethodGet, "/api/v1/auth/me", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("登出后会话应失效，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

func TestChangePasswordInvalidatesAllSessions(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	cookie := registerAndLogin(t, ts, "a@example.com")

	// 当前密码错误 → 403
	res := ts.do(t, http.MethodPost, "/api/v1/auth/change-password", map[string]string{
		"current_password": "wrong", "new_password": "newpw",
	}, map[string]string{"Cookie": "driftclip_session=" + cookie, "X-Requested-With": "XMLHttpRequest"})
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("错误当前密码应 403，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 正确修改 → 会话全部失效
	res = ts.do(t, http.MethodPost, "/api/v1/auth/change-password", map[string]string{
		"current_password": "pw123", "new_password": "newpw",
	}, map[string]string{"Cookie": "driftclip_session=" + cookie, "X-Requested-With": "XMLHttpRequest"})
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("改密失败: %d", res.StatusCode)
	}
	res.Body.Close()

	res = ts.do(t, http.MethodGet, "/api/v1/auth/me", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("改密后旧会话应失效，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 新密码可登录
	res = ts.do(t, http.MethodPost, "/api/v1/auth/login", map[string]string{
		"email": "a@example.com", "password": "newpw",
	}, nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("新密码登录失败: %d", res.StatusCode)
	}
	res.Body.Close()
}

// ---- CSRF：会话状态修改需自定义请求头，Key 请求不受影响 ----

func TestCSRF(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	cookie := registerAndLogin(t, ts, "a@example.com")

	// 会话请求无 X-Requested-With → 403
	res := ts.do(t, http.MethodPost, "/api/v1/keys", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("无 CSRF 头的会话状态修改应 403，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 带 CSRF 头 → 成功
	res = ts.do(t, http.MethodPost, "/api/v1/keys", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("带 CSRF 头应成功，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

// ---- 筛选与分页 ----

func TestListFiltersAndPagination(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")

	samples := []struct {
		content  string
		source   string
		platform string
	}{
		{"Hello World macOS", "clipboard", "macos"},
		{"hello world windows", "clipboard", "windows"},
		{"完全不同的内容 Linux", "manual", "linux"},
		{"HELLO WORLD ios", "clipboard", "ios"},
	}
	for _, s := range samples {
		res := upload(t, ts, key, testBody(s.content, s.source, s.platform))
		if res.StatusCode != http.StatusCreated {
			t.Fatalf("上传失败: %d", res.StatusCode)
		}
		res.Body.Close()
	}

	// 平台筛选
	res := ts.do(t, http.MethodGet, "/api/v1/history?platform=macos", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	var out map[string]any
	decode(t, res, &out)
	if out["total"].(float64) != 1 {
		t.Fatalf("platform=macos 应 1 条，实际 %v", out["total"])
	}

	// 正文子串（忽略英文字母大小写）→ "HELLO WORLD" 命中 2 条（macos 与 windows、ios 中 …）
	res = ts.do(t, http.MethodGet, "/api/v1/history?q=hello%20world", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	decode(t, res, &out)
	if out["total"].(float64) != 3 {
		t.Fatalf("q=hello world 应命中 3 条，实际 %v", out["total"])
	}

	// 组合：platform=ios + q=hello → 1 条
	res = ts.do(t, http.MethodGet, "/api/v1/history?platform=ios&q=hello", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	decode(t, res, &out)
	if out["total"].(float64) != 1 {
		t.Fatalf("组合筛选应 1 条，实际 %v", out["total"])
	}

	// 分页：page_size=2 第 1 页 → 2 条，total=4
	res = ts.do(t, http.MethodGet, "/api/v1/history?page_size=2&page=1", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	decode(t, res, &out)
	if out["total"].(float64) != 4 || len(out["items"].([]any)) != 2 {
		t.Fatalf("分页结果错误: %v", out)
	}

	// 时间范围筛选：from=未来时间 → 0 条
	res = ts.do(t, http.MethodGet, "/api/v1/history?from=2099-01-01", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	decode(t, res, &out)
	if out["total"].(float64) != 0 {
		t.Fatalf("from=2099 应 0 条，实际 %v", out["total"])
	}
}

// ---- 删除与清空 ----

func TestDeleteBatchAndClear(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	_, key := createKey(t, ts, "a@example.com")
	ids := make([]int64, 0, 3)
	for i := 0; i < 3; i++ {
		res := upload(t, ts, key, testBody("del-"+itoa(int64(i)), "manual", "macos"))
		var up map[string]any
		decode(t, res, &up)
		ids = append(ids, int64(up["id"].(float64)))
	}

	// 单条删除
	res := ts.do(t, http.MethodDelete, "/api/v1/history/"+itoa(ids[0]), nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("单删失败: %d", res.StatusCode)
	}
	res.Body.Close()

	// 批量删除剩余两条
	res = ts.do(t, http.MethodPost, "/api/v1/history/batch-delete",
		map[string]any{"ids": []int64{ids[1], ids[2]}},
		map[string]string{"Authorization": "Bearer " + key})
	var del map[string]any
	decode(t, res, &del)
	if del["deleted"].(float64) != 2 {
		t.Fatalf("批量删除应删 2 条，实际 %v", del["deleted"])
	}

	// 清空
	res = ts.do(t, http.MethodPost, "/api/v1/history/clear", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	decode(t, res, &del)
	if del["deleted"].(float64) != 0 {
		t.Fatalf("清空应删 0 条（已空），实际 %v", del["deleted"])
	}
}

// ---- Key 生命周期 ----

func TestKeyGenerationAndResetRules(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	cookie := registerAndLogin(t, ts, "a@example.com")

	// 未生成 Key 时上传 → 401（Key 不存在）
	res := ts.do(t, http.MethodPost, "/api/v1/history", testBody("x", "manual", "macos"), map[string]string{
		"Authorization": "Bearer dc_nonexistent",
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("无 Key 上传应 401，实际 %d", res.StatusCode)
	}
	res.Body.Close()

	// 生成 Key
	res = ts.do(t, http.MethodPost, "/api/v1/keys", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	var out map[string]string
	decode(t, res, &out)
	if !strings.HasPrefix(out["key"], "dc_") {
		t.Fatalf("Key 应以 dc_ 开头，实际 %q", out["key"])
	}

	// 重复生成 → 409
	res = ts.do(t, http.MethodPost, "/api/v1/keys", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	if res.StatusCode != http.StatusConflict {
		t.Fatalf("重复生成应 409，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

// ---- 评审修复回归测试（F1/F3/F4/F7/F12/Q2）----

func TestListOmitsPublicIPAndFullContent(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()
	_, key := createKey(t, ts, "a@example.com")
	res := upload(t, ts, key, testBody("投影测试", "clipboard", "macos"))
	res.Body.Close()

	res = ts.do(t, http.MethodGet, "/api/v1/history", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	var out map[string]any
	decode(t, res, &out)
	item := out["items"].([]any)[0].(map[string]any)
	if _, present := item["public_ip"]; present {
		t.Fatal("列表项不应包含 public_ip 字段（字段投影）")
	}
	if _, present := item["content"]; present {
		t.Fatal("列表项不应包含完整 content 字段（字段投影）")
	}
	if item["content_preview"] != "投影测试" {
		t.Fatalf("应返回内容预览，实际 %v", item["content_preview"])
	}
}

func TestBusinessTimezoneIsUTC8(t *testing.T) {
	ts := newTestServer(t, testOpts{location: "Asia/Shanghai"})
	defer ts.close()
	_, key := createKey(t, ts, "a@example.com")
	res := upload(t, ts, key, testBody("时区", "manual", "macos"))
	var up map[string]any
	decode(t, res, &up)
	if !strings.HasSuffix(up["received_at"].(string), "+08:00") {
		t.Fatalf("received_at 应按 UTC+8 展示，实际 %v", up["received_at"])
	}
}

func TestManualWhitespaceOnlyRejected(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()
	_, key := createKey(t, ts, "a@example.com")
	// manual 来源去除首尾空格后为空 → 400（Spec §3.2，评审 F4）
	res := upload(t, ts, key, testBody("   \t  ", "manual", "macos"))
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("manual 纯空格应 400，实际 %d", res.StatusCode)
	}
	res.Body.Close()
	// clipboard 来源允许纯空格（契约只约束 manual）
	res = upload(t, ts, key, testBody("   ", "clipboard", "macos"))
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("clipboard 纯空格应 201，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

func TestKeyStatusEndpoint(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()
	cookie := registerAndLogin(t, ts, "a@example.com")

	// 无 Key 时 has_key=false
	res := ts.do(t, http.MethodGet, "/api/v1/keys", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	var out map[string]bool
	decode(t, res, &out)
	if out["has_key"] {
		t.Fatal("未生成 Key 时 has_key 应为 false")
	}

	// 生成 Key 后 has_key=true
	res = ts.do(t, http.MethodPost, "/api/v1/keys", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	res.Body.Close()
	res = ts.do(t, http.MethodGet, "/api/v1/keys", nil, map[string]string{
		"Cookie": "driftclip_session=" + cookie,
	})
	decode(t, res, &out)
	if !out["has_key"] {
		t.Fatal("生成 Key 后 has_key 应为 true")
	}
}

func TestResetWithoutKeyReturns409(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()
	cookie := registerAndLogin(t, ts, "a@example.com")
	// 账户尚无 Key 时重置 → 409（评审 Q2）
	res := ts.do(t, http.MethodPost, "/api/v1/keys/reset", nil, map[string]string{
		"Cookie":           "driftclip_session=" + cookie,
		"X-Requested-With": "XMLHttpRequest",
	})
	if res.StatusCode != http.StatusConflict {
		t.Fatalf("无 Key 重置应 409，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

func TestHTTPSRespectsTrustedProxies(t *testing.T) {
	ts := newTestServer(t, testOpts{requireHTTPS: true, trustedProxies: []string{"192.0.2.0/24"}})
	defer ts.close()

	// 不可信来源伪造 X-Forwarded-Proto: https → 仍拒绝（评审 F1）
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login",
		bytes.NewBufferString(`{"email":"a@example.com","password":"x"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Forwarded-Proto", "https")
	req.RemoteAddr = "198.51.100.9:1000"
	rec := httptest.NewRecorder()
	ts.h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("不可信来源的 XFP https 应被拒，实际 %d", rec.Code)
	}

	// 可信代理来源 + XFP https → 通过 HTTPS 检查（登录失败返回 401 而非 400）
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login",
		bytes.NewBufferString(`{"email":"a@example.com","password":"wrong"}`))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("X-Forwarded-Proto", "https")
	req2.RemoteAddr = "192.0.2.9:1000"
	rec2 := httptest.NewRecorder()
	ts.h.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusUnauthorized {
		t.Fatalf("可信代理应通过 HTTPS 检查，实际 %d", rec2.Code)
	}
}

func TestPublicEndpointsExemptFromCSRF(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()
	cookie := registerAndLogin(t, ts, "first@example.com")
	// 持有旧会话 Cookie 再注册新账户（无 CSRF 头）→ 公开端点应豁免（评审 F3）
	res := ts.do(t, http.MethodPost, "/api/v1/auth/register",
		map[string]string{"email": "second@example.com", "password": "pw123"},
		map[string]string{"Cookie": "driftclip_session=" + cookie})
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("公开端点应豁免 CSRF，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

func TestPageOverflowRejected(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()
	_, key := createKey(t, ts, "a@example.com")
	res := ts.do(t, http.MethodGet, "/api/v1/history?page=999999999999", nil, map[string]string{
		"Authorization": "Bearer " + key,
	})
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("超大 page 应 400 而非 500，实际 %d", res.StatusCode)
	}
	res.Body.Close()
}

// ---- 辅助 ----

func itoa(v int64) string {
	return strconv.FormatInt(v, 10)
}
