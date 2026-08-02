package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

var ErrDuplicateEmail = errors.New("邮箱已注册")

type Account struct {
	ID           int64
	Email        string
	PasswordHash string
	CreatedAt    time.Time
}

// CreateAccount 创建账户。邮箱必须已规范化（trim + 小写）并由调用方校验格式。
// 返回 ErrDuplicateEmail 表示邮箱已存在。
func (s *Store) CreateAccount(ctx context.Context, email, passwordHash string) (*Account, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO accounts (email, password_hash, created_at) VALUES (?, ?, ?)`,
		email, passwordHash, nowUTC())
	if err != nil {
		if isConstraintError(err) {
			return nil, ErrDuplicateEmail
		}
		return nil, err
	}
	id, _ := res.LastInsertId()
	return &Account{ID: id, Email: email, PasswordHash: passwordHash, CreatedAt: time.Now().UTC()}, nil
}

func (s *Store) GetAccountByEmail(ctx context.Context, email string) (*Account, error) {
	return s.scanAccount(s.db.QueryRowContext(ctx,
		`SELECT id, email, password_hash, created_at FROM accounts WHERE email = ?`, email))
}

func (s *Store) GetAccountByID(ctx context.Context, id int64) (*Account, error) {
	return s.scanAccount(s.db.QueryRowContext(ctx,
		`SELECT id, email, password_hash, created_at FROM accounts WHERE id = ?`, id))
}

// UpdatePassword 更新密码哈希并返回受影响行数（账户不存在时为 0）。
func (s *Store) UpdatePassword(ctx context.Context, accountID int64, passwordHash string) (int64, error) {
	res, err := s.db.ExecContext(ctx,
		`UPDATE accounts SET password_hash = ? WHERE id = ?`, passwordHash, accountID)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// ChangePasswordAndRevokeSessions 在同一事务内更新密码并作废该账户全部会话。
// 保证「改密成功 → 所有 Web 会话立即失效」是原子的，故障时不会出现
// 密码已改但旧会话仍有效的中间状态（评审 F5）。
func (s *Store) ChangePasswordAndRevokeSessions(ctx context.Context, accountID int64, passwordHash string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE accounts SET password_hash = ? WHERE id = ?`, passwordHash, accountID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM sessions WHERE account_id = ?`, accountID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) scanAccount(row *sql.Row) (*Account, error) {
	var a Account
	var createdAt string
	if err := row.Scan(&a.ID, &a.Email, &a.PasswordHash, &createdAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	t, err := time.Parse(time.RFC3339, createdAt)
	if err != nil {
		return nil, err
	}
	a.CreatedAt = t
	return &a, nil
}
