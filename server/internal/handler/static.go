package handler

import (
	"net/http"
	"os"
	"path/filepath"
)

// StaticHandler 服务 React 静态产物（web/dist），并支持 SPA 客户端路由 fallback：
// 命中的静态文件直接服务，未命中（客户端路由如 /keys）回落到 index.html。
// /api 前缀的请求由外层路由分流，不进入本处理器。
func StaticHandler(staticDir string) http.Handler {
	fs := http.FileServer(http.Dir(staticDir))
	indexPath := filepath.Join(staticDir, "index.html")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.NotFound(w, r)
			return
		}
		candidate := filepath.Join(staticDir, filepath.Clean("/"+r.URL.Path))
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			fs.ServeHTTP(w, r)
			return
		}
		http.ServeFile(w, r, indexPath)
	})
}
