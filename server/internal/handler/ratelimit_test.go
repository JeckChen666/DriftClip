package handler_test

// ROADMAP P3.1/P3.3：内存限流与 /api/v1/meta 端点。

import (
	"encoding/json"
	"net/http"
	"testing"

	"driftclip/server/internal/handler"
)

func TestAuthRateLimitByIP(t *testing.T) {
	ts := newTestServer(t, testOpts{authLimit: 2})
	defer ts.close()

	body := map[string]any{"email": "ratelimit@example.com", "password": "pw"}
	// 窗口内前两次放行（无论成功失败），第三次返回 429。
	for i := 0; i < 2; i++ {
		res := ts.do(t, "POST", "/api/v1/auth/login", body, nil)
		res.Body.Close()
		if res.StatusCode == http.StatusTooManyRequests {
			t.Fatalf("第 %d 次请求不应被限流", i+1)
		}
	}
	res := ts.do(t, "POST", "/api/v1/auth/login", body, nil)
	defer res.Body.Close()
	if res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("期望 429，实际 %d", res.StatusCode)
	}
}

func TestUploadRateLimitByAccount(t *testing.T) {
	ts := newTestServer(t, testOpts{uploadLimit: 2})
	defer ts.close()

	_, key := createKey(t, ts, "upload-limit@example.com")
	for i := 0; i < 2; i++ {
		res := upload(t, ts, key, testBody("hello", "clipboard", "macos"))
		res.Body.Close()
		if res.StatusCode != http.StatusCreated {
			t.Fatalf("第 %d 次上传不应被限流，实际 %d", i+1, res.StatusCode)
		}
	}
	res := upload(t, ts, key, testBody("hello-2", "clipboard", "macos"))
	defer res.Body.Close()
	if res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("期望 429，实际 %d", res.StatusCode)
	}
}

func TestRateLimitDisabledByDefault(t *testing.T) {
	ts := newTestServer(t, testOpts{})
	defer ts.close()

	// 未配置限流器时连续多次请求均放行。
	for i := 0; i < 5; i++ {
		res := ts.do(t, "POST", "/api/v1/auth/login", map[string]any{
			"email": "off@example.com", "password": "pw",
		}, nil)
		res.Body.Close()
		if res.StatusCode == http.StatusTooManyRequests {
			t.Fatalf("未启用限流时不应返回 429")
		}
	}
}

func TestMetaEndpoint(t *testing.T) {
	ts := newTestServer(t, testOpts{maxRecords: 555})
	defer ts.close()

	res := ts.do(t, "GET", "/api/v1/meta", nil, nil)
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("期望 200，实际 %d", res.StatusCode)
	}
	var got struct {
		Version               string `json:"version"`
		MaxHistoryRecords     int    `json:"max_history_records"`
		MaxClipboardTextBytes int64  `json:"max_clipboard_text_bytes"`
	}
	if err := json.NewDecoder(res.Body).Decode(&got); err != nil {
		t.Fatalf("解码 meta 响应: %v", err)
	}
	if got.Version != handler.ServerVersion {
		t.Fatalf("version = %q, 期望 %q", got.Version, handler.ServerVersion)
	}
	if got.MaxHistoryRecords != 555 {
		t.Fatalf("max_history_records = %d, 期望 555", got.MaxHistoryRecords)
	}
	if got.MaxClipboardTextBytes != 102400 {
		t.Fatalf("max_clipboard_text_bytes = %d, 期望 102400", got.MaxClipboardTextBytes)
	}
}
