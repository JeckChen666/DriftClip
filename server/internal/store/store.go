// Package store 封装 SQLite 持久化：Schema 迁移、账户/会话/Key/历史记录
// 的 CRUD 以及按账户的保留策略清理。
//
// 时间约定：所有存储时间使用 RFC3339 UTC（如 "2026-08-02T11:00:00Z"）。
// RFC3339 UTC 字符串的字典序即时间序，因此 received_at 可直接用于排序比较；
// 同秒多条以自增 id 决胜（业务排序稳定键，见 Spec 工程默认实践）。
package store

import (
	"database/sql"
	"fmt"
	"net/url"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct {
	db               *sql.DB
	location         *time.Location
	MaxHistoryRecords int
}

// Open 打开（必要时创建）SQLite 数据库，执行 Schema 迁移并启用 WAL。
func Open(path string, location *time.Location, maxHistoryRecords int) (*Store, error) {
	// _pragma 由 modernc.org/sqlite 解析并应用到每个连接：
	// journal_mode=WAL（并发读写）、busy_timeout=5000（写锁等待，避免 SQLITE_BUSY）、
	// foreign_keys=ON（约束引用完整性）。
	dsn := "file:" + url.PathEscape(path) +
		"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("打开数据库 %s: %w", path, err)
	}
	// WAL 下允许少量并发读；写由 busy_timeout 串行等待。
	db.SetMaxOpenConns(8)

	s := &Store{db: db, location: location, MaxHistoryRecords: maxHistoryRecords}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, fmt.Errorf("执行 Schema 迁移: %w", err)
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate() error {
	_, err := s.db.Exec(`
CREATE TABLE IF NOT EXISTS accounts (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  email         TEXT NOT NULL UNIQUE,          -- 规范化邮箱（去空格转小写），全局唯一
  password_hash TEXT NOT NULL,                 -- Argon2id 哈希，绝不存明文
  created_at    TEXT NOT NULL                  -- RFC3339 UTC
);

CREATE TABLE IF NOT EXISTS sessions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id  INTEGER NOT NULL REFERENCES accounts(id),
  token_hash  TEXT NOT NULL UNIQUE,            -- SHA-256(session_token)
  expires_at  TEXT NOT NULL                    -- RFC3339 UTC
);

-- 按账户作废全部会话（改密）的查询索引（评审 F6）。
CREATE INDEX IF NOT EXISTS idx_sessions_account ON sessions (account_id);

-- 每账户只有一个有效 Key（account_id 主键）；key_hash 全局唯一。
CREATE TABLE IF NOT EXISTS keys (
  account_id  INTEGER PRIMARY KEY REFERENCES accounts(id),
  key_hash    TEXT NOT NULL UNIQUE,            -- HMAC-SHA256(key_pepper, key)
  created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS history (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id      INTEGER NOT NULL REFERENCES accounts(id),
  content         TEXT NOT NULL,
  source          TEXT NOT NULL,               -- 'clipboard' | 'manual'
  received_at     TEXT NOT NULL,               -- RFC3339 UTC，排序/保留唯一依据
  public_ip       TEXT NOT NULL,               -- 服务端观测到的公网 IP
  platform        TEXT NOT NULL,
  os_version      TEXT,
  device_model    TEXT,
  app_version     TEXT,
  installation_id TEXT
);

-- 列表排序与保留清理共用的复合索引（received_at 降序 + id 决胜）。
CREATE INDEX IF NOT EXISTS idx_history_account_time
  ON history (account_id, received_at DESC, id DESC);
`)
	return err
}

// nowUTC 返回当前 UTC 时间的 RFC3339 字符串（与存储格式一致）。
func nowUTC() string { return time.Now().UTC().Format(time.RFC3339) }

// formatUTC 把 time.Time 归一化为 RFC3339 UTC。
func formatUTC(t time.Time) string { return t.UTC().Format(time.RFC3339) }
