// Package config 负责加载和校验 DriftClip 服务端配置。
//
// 配置来源优先级：默认值 < YAML 文件 < 环境变量（DRIFTCLIP_*）。
// YAML 键名与 CLIPBOARD_SYNC_V1_PLAN.md §8.2 保持一致。
package config

import (
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

const envPrefix = "DRIFTCLIP_"

type Config struct {
	Server       ServerConfig       `yaml:"server"`
	Registration RegistrationConfig `yaml:"registration"`
	History      HistoryConfig      `yaml:"history"`
	Security     SecurityConfig     `yaml:"security"`
	Database     DatabaseConfig     `yaml:"database"`
	Web          WebConfig          `yaml:"web"`

	// 以下字段为加载后解析出的运行态值，不来自 YAML。
	Location   *time.Location // business_timezone 解析结果
	TrustedNets []*net.IPNet   // trusted_proxies 解析结果
}

type ServerConfig struct {
	ListenAddr     string   `yaml:"listen_addr"`
	BusinessTZ     string   `yaml:"business_timezone"`
	TrustedProxies []string `yaml:"trusted_proxies"`
	// RequireHTTPS 开启后拒绝非 HTTPS 请求（部署层由反向代理终止 TLS，
	// 应用检查 X-Forwarded-Proto）。本地开发关闭。
	RequireHTTPS bool `yaml:"require_https"`
}

type RegistrationConfig struct {
	Enabled bool `yaml:"enabled"`
}

type HistoryConfig struct {
	MaxHistoryRecords    int   `yaml:"max_history_records"`
	MaxClipboardTextBytes int64 `yaml:"max_clipboard_text_bytes"`
}

type SecurityConfig struct {
	SessionDurationDays int    `yaml:"session_duration_days"`
	SessionSecret       string `yaml:"session_secret"`
	KeyPepper           string `yaml:"key_pepper"`
}

type DatabaseConfig struct {
	Path string `yaml:"path"`
}

// WebConfig 是 React 静态产物托管配置。
type WebConfig struct {
	// StaticDir 为 React 构建产物目录（web/dist）。为空则不停托 Web（仅 API）。
	// 部署时由 Docker 构建阶段写入产物，或通过 DRIFTCLIP_WEB_STATIC_DIR 覆盖。
	StaticDir string `yaml:"static_dir"`
}

// Load 从 YAML 文件（可选）、环境变量与默认值构建配置。
// configPath 为空时只使用默认值与环境变量。
func Load(configPath string) (*Config, error) {
	cfg := defaults()
	if configPath != "" {
		data, err := os.ReadFile(configPath)
		if err != nil {
			return nil, fmt.Errorf("读取配置文件 %s: %w", configPath, err)
		}
		if err := yaml.Unmarshal(data, cfg); err != nil {
			return nil, fmt.Errorf("解析配置文件 %s: %w", configPath, err)
		}
	}
	applyEnv(cfg)

	// 解析业务时区
	tzName := cfg.Server.BusinessTZ
	if tzName == "" {
		tzName = "Asia/Shanghai"
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		return nil, fmt.Errorf("无效业务时区 %q: %w", tzName, err)
	}
	cfg.Location = loc

	// 解析可信代理
	for _, p := range cfg.Server.TrustedProxies {
		_, ipnet, err := net.ParseCIDR(p)
		if err != nil {
			return nil, fmt.Errorf("无效 trusted_proxy %q（需为 CIDR）: %w", p, err)
		}
		cfg.TrustedNets = append(cfg.TrustedNets, ipnet)
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func defaults() *Config {
	return &Config{
		Server: ServerConfig{
			ListenAddr:  "0.0.0.0:8080",
			BusinessTZ:  "Asia/Shanghai",
			RequireHTTPS: false,
		},
		Registration: RegistrationConfig{Enabled: true},
		History: HistoryConfig{
			MaxHistoryRecords:     100,
			MaxClipboardTextBytes: 102400,
		},
		Security: SecurityConfig{
			SessionDurationDays: 30,
			SessionSecret:       "replace-with-a-long-random-secret",
			KeyPepper:           "replace-with-a-separate-long-random-secret",
		},
		Database: DatabaseConfig{Path: "driftclip.sqlite"},
		Web:      WebConfig{StaticDir: "web/dist"},
	}
}

func applyEnv(c *Config) {
	if v := os.Getenv(envPrefix + "SERVER_LISTEN_ADDR"); v != "" {
		c.Server.ListenAddr = v
	}
	if v := os.Getenv(envPrefix + "SERVER_BUSINESS_TZ"); v != "" {
		c.Server.BusinessTZ = v
	}
	if v := os.Getenv(envPrefix + "SERVER_REQUIRE_HTTPS"); v != "" {
		c.Server.RequireHTTPS = v == "true" || v == "1"
	}
	// 逗号分隔的可信代理 CIDR 列表（Docker 部署常用环境变量配置）。
	if v := os.Getenv(envPrefix + "SERVER_TRUSTED_PROXIES"); v != "" {
		parts := strings.Split(v, ",")
		c.Server.TrustedProxies = c.Server.TrustedProxies[:0]
		for _, p := range parts {
			if t := strings.TrimSpace(p); t != "" {
				c.Server.TrustedProxies = append(c.Server.TrustedProxies, t)
			}
		}
	}
	if v := os.Getenv(envPrefix + "REGISTRATION_ENABLED"); v != "" {
		c.Registration.Enabled = v == "true" || v == "1"
	}
	if v := os.Getenv(envPrefix + "HISTORY_MAX_RECORDS"); v != "" {
		fmt.Sscanf(v, "%d", &c.History.MaxHistoryRecords)
	}
	if v := os.Getenv(envPrefix + "HISTORY_MAX_TEXT_BYTES"); v != "" {
		fmt.Sscanf(v, "%d", &c.History.MaxClipboardTextBytes)
	}
	if v := os.Getenv(envPrefix + "SESSION_DURATION_DAYS"); v != "" {
		fmt.Sscanf(v, "%d", &c.Security.SessionDurationDays)
	}
	if v := os.Getenv(envPrefix + "SESSION_SECRET"); v != "" {
		c.Security.SessionSecret = v
	}
	if v := os.Getenv(envPrefix + "KEY_PEPPER"); v != "" {
		c.Security.KeyPepper = v
	}
	if v := os.Getenv(envPrefix + "DATABASE_PATH"); v != "" {
		c.Database.Path = v
	}
	if v := os.Getenv(envPrefix + "WEB_STATIC_DIR"); v != "" {
		c.Web.StaticDir = v
	}
}

func (c *Config) validate() error {
	if c.History.MaxHistoryRecords < 1 {
		return fmt.Errorf("history.max_history_records 必须 ≥ 1")
	}
	if c.History.MaxClipboardTextBytes < 1 {
		return fmt.Errorf("history.max_clipboard_text_bytes 必须 ≥ 1")
	}
	if c.Security.SessionDurationDays < 1 {
		return fmt.Errorf("security.session_duration_days 必须 ≥ 1")
	}
	if c.Security.SessionSecret == "" {
		return fmt.Errorf("security.session_secret 不能为空")
	}
	if c.Security.KeyPepper == "" {
		return fmt.Errorf("security.key_pepper 不能为空")
	}
	return nil
}

// UsesPlaceholderSecrets 报告密钥是否仍是占位默认值（生产部署应被替换）。
func (c *Config) UsesPlaceholderSecrets() bool {
	return c.Security.SessionSecret == "replace-with-a-long-random-secret" ||
		c.Security.KeyPepper == "replace-with-a-separate-long-random-secret"
}
