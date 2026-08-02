// Command driftclip-server 是 DriftClip 服务端入口。
//
// 启动流程：加载配置 → 打开数据库并迁移 → 启动时保留清理 → 装配路由 → 监听。
package main

import (
	"context"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"driftclip/server/internal/config"
	"driftclip/server/internal/handler"
	"driftclip/server/internal/store"
)

func main() {
	configPath := flag.String("config", "", "YAML 配置文件路径（默认使用环境变量与默认值）")
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		slog.Error("加载配置失败", "err", err)
		os.Exit(1)
	}
	if cfg.UsesPlaceholderSecrets() {
		slog.Warn("session_secret / key_pepper 仍是占位默认值，生产部署必须替换（Spec §8.2）")
	}
	if !cfg.Server.RequireHTTPS {
		slog.Warn("require_https 未开启：生产部署必须由反向代理强制 HTTPS（评审 Q1）")
	}

	st, err := store.Open(cfg.Database.Path, cfg.Location, cfg.History.MaxHistoryRecords)
	if err != nil {
		slog.Error("打开数据库失败", "err", err)
		os.Exit(1)
	}
	defer st.Close()

	// 启动时保留清理：配置上限被调低时立即把每个账户清理到新上限（Spec §3.4）。
	// 清理失败视为致命错误，不允许带着超限状态静默启动（评审 F11）。
	ctx := context.Background()
	if n, err := st.CleanupAccounts(ctx); err != nil {
		slog.Error("启动保留清理失败", "err", err)
		os.Exit(1)
	} else if n > 0 {
		slog.Info("启动保留清理完成", "deleted_records", n)
	}
	// 清理已过期会话行，防止 sessions 表无限增长（评审 F6）。
	if n, err := st.DeleteExpiredSessions(ctx); err != nil {
		slog.Warn("清理过期会话失败", "err", err)
	} else if n > 0 {
		slog.Info("清理过期会话完成", "deleted_sessions", n)
	}

	srv := &handler.Server{
		Store:                 st,
		Location:              cfg.Location,
		SessionDuration:       time.Duration(cfg.Security.SessionDurationDays) * 24 * time.Hour,
		SessionSecret:         cfg.Security.SessionSecret,
		KeyPepper:             cfg.Security.KeyPepper,
		RegistrationEnabled:   cfg.Registration.Enabled,
		MaxClipboardTextBytes: cfg.History.MaxClipboardTextBytes,
		TrustedNets:           cfg.TrustedNets,
		SecureCookies:         cfg.Server.RequireHTTPS,
		RequireHTTPS:          cfg.Server.RequireHTTPS,
	}

	// 路由装配：/api 走 API，其余托管 React 静态产物（web/dist，SPA fallback）。
	var root http.Handler = srv.Routes()
	if cfg.Web.StaticDir != "" {
		staticDir := cfg.Web.StaticDir
		if _, err := os.Stat(staticDir); err != nil {
			// 从 server/ 目录本地运行时，配置默认值 web/dist 指向仓库根，回退尝试上一级
			if _, err := os.Stat("../" + staticDir); err == nil {
				staticDir = "../" + staticDir
			}
		}
		if _, err := os.Stat(staticDir); err == nil {
			mux := http.NewServeMux()
			mux.Handle("/api/", root)
			mux.Handle("/", handler.StaticHandler(staticDir))
			root = mux
		} else {
			slog.Warn("web.static_dir 不存在，仅提供 API", "dir", cfg.Web.StaticDir)
		}
	}

	httpSrv := &http.Server{
		Addr:              cfg.Server.ListenAddr,
		Handler:           root,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		slog.Info("服务启动", "addr", cfg.Server.ListenAddr, "timezone", cfg.Location.String(), "max_records", cfg.History.MaxHistoryRecords)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("HTTP 服务异常退出", "err", err)
			os.Exit(1)
		}
	}()

	// 优雅退出：等待 SIGINT/SIGTERM。
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	slog.Info("收到退出信号，正在关闭…")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		slog.Warn("关闭服务出错", "err", err)
	}
	slog.Info("服务已退出")
}
