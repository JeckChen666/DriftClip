package middleware

import (
	"strconv"
	"testing"
	"time"
)

func TestRateLimiterWindowSlides(t *testing.T) {
	now := time.Unix(0, 0)
	l := NewRateLimiter(2, time.Minute)
	l.now = func() time.Time { return now }

	if !l.Allow("a") || !l.Allow("a") {
		t.Fatal("窗口内前两次应放行")
	}
	if l.Allow("a") {
		t.Fatal("第三次应被限流")
	}
	// 不同 key 互不影响。
	if !l.Allow("b") {
		t.Fatal("不同 key 应独立计数")
	}
	// 窗口滑过之后配额恢复。
	now = now.Add(2 * time.Minute)
	if !l.Allow("a") {
		t.Fatal("窗口滑动后应放行")
	}
}

func TestRateLimiterSweepKeepsMapBounded(t *testing.T) {
	now := time.Unix(0, 0)
	l := NewRateLimiter(1, time.Second)
	l.now = func() time.Time { return now }
	// 制造大量过期 key，超过 maxTrackedKeys 触发清理（此时窗口未滑过、不删）。
	for i := 0; i < 5000; i++ {
		l.Allow(strconv.Itoa(i))
	}
	// 时间跳过窗口后，下一次 Allow 触发清理，过期 key 全部移除。
	now = now.Add(time.Hour)
	l.Allow("trigger-sweep")
	if len(l.visits) > 10 {
		t.Fatalf("过期 key 应被清理，剩余 %d 个", len(l.visits))
	}
}
