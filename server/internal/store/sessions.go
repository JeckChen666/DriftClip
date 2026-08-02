package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

type Session struct {
	ID        int64
	AccountID int64
	TokenHash string
	ExpiresAt time.Time
}

// CreateSession 建立会话。tokenHash 是会话 token 的 SHA-256（不存原始 token）。
func (s *Store) CreateSession(ctx context.Context, accountID int64, tokenHash string, expiresAt time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sessions (account_id, token_hash, expires_at) VALUES (?, ?, ?)`,
		accountID, tokenHash, formatUTC(expiresAt))
	return err
}

// GetSessionByTokenHash 按 token 哈希查找未过期会话。
func (s *Store) GetSessionByTokenHash(ctx context.Context, tokenHash string) (*Session, error) {
	var sess Session
	var expires string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, token_hash, expires_at FROM sessions WHERE token_hash = ?`, tokenHash).
		Scan(&sess.ID, &sess.AccountID, &sess.TokenHash, &expires)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	exp, err := time.Parse(time.RFC3339, expires)
	if err != nil {
		return nil, err
	}
	sess.ExpiresAt = exp
	// 过期会话视为不存在（并惰性清理，避免每次读都过滤）。
	if exp.Before(time.Now()) {
		return nil, nil
	}
	return &sess, nil
}

func (s *Store) DeleteSession(ctx context.Context, tokenHash string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, tokenHash)
	return err
}

// DeleteAllSessionsForAccount 作废某账户的全部会话（修改密码后调用）。
func (s *Store) DeleteAllSessionsForAccount(ctx context.Context, accountID int64) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE account_id = ?`, accountID)
	return err
}

// DeleteExpiredSessions 删除所有已过期的会话行（启动时调用，避免表无限增长，评审 F6）。
func (s *Store) DeleteExpiredSessions(ctx context.Context) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE expires_at < ?`, nowUTC())
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
