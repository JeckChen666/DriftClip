// 基于内存的滑动窗口限流（ROADMAP P3.1）。
//
// 单二进制单机部署无需外部依赖；每个进程独立计数（当前不支持水平扩展，
// 多实例部署时计数不共享）。公开端点（注册/登录）按来源 IP 限流防爆破，
// 上传按账户限流防刷。
package middleware

import (
	"encoding/json"
	"net"
	"net/http"
	"sync"
	"time"
)

// RateLimiter 是按 key 记录访问时间戳的滑动窗口计数器。
type RateLimiter struct {
	mu     sync.Mutex
	visits map[string][]time.Time
	limit  int
	window time.Duration
	now    func() time.Time // 可注入（测试）
	sweeps int              // allow 计数，用于周期性清理过期 key
}

// NewRateLimiter 创建窗口内最多 limit 次的限流器。
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		visits: make(map[string][]time.Time),
		limit:  limit,
		window: window,
		now:    time.Now,
	}
}

// Allow 报告 key 在当前窗口内是否还有配额，有则记录本次访问。
func (l *RateLimiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	cutoff := now.Add(-l.window)

	visits := l.visits[key]
	kept := visits[:0]
	for _, t := range visits {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= l.limit {
		l.visits[key] = kept
		return false
	}
	l.visits[key] = append(kept, now)

	// 防止长期运行时 map 无限增长：按调用次数或 key 规模周期性清理过期 key。
	l.sweeps++
	if l.sweeps >= 1024 || len(l.visits) > maxTrackedKeys {
		l.sweeps = 0
		for k, ts := range l.visits {
			live := ts[:0]
			for _, t := range ts {
				if t.After(cutoff) {
					live = append(live, t)
				}
			}
			if len(live) == 0 {
				delete(l.visits, k)
			} else {
				l.visits[k] = live
			}
		}
	}
	return true
}

// maxTrackedKeys 限制 key 规模：超过即触发一次全量过期清理，
// 保证被限流键（如大量伪造来源 IP）不会撑爆内存。
const maxTrackedKeys = 4096

// RateLimit 用 keyFn(r) 作为限流键包装 next。limiter 为 nil 时直接放行
// （rate_limit.enabled=false 或测试未配置）。
func RateLimit(limiter *RateLimiter, keyFn func(*http.Request) string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if limiter != nil && !limiter.Allow(keyFn(r)) {
			w.Header().Set("Retry-After", "60")
			writeRateLimitError(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeRateLimitError(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusTooManyRequests)
	json.NewEncoder(w).Encode(map[string]string{"error": "请求过于频繁，请稍后再试"})
}

// DirectIP 返回直接连接地址（不含端口），用作限流键的保守实现：
// 不解析转发头，避免客户端伪造 X-Forwarded-For 绕过限流；
// 反向代理场景下由部署方通过 trusted_proxies + handler.Server.clientIP 提供真实 IP。
func DirectIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	return host
}
