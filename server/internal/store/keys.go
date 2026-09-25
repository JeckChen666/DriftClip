package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// ErrKeyExists 表示账户已有有效 Key（需用重置而非再次生成）。
var ErrKeyExists = errors.New("该账户已存在有效 Key，如需更换请使用重置")

type APIKey struct {
	AccountID int64
	KeyHash   string
	CreatedAt time.Time
}

// InsertKey 写入账户的 Key 哈希与加密原文（Web 回显用）。
// 账户已有 Key 时返回 ErrKeyExists（不允许静默覆盖）。
func (s *Store) InsertKey(ctx context.Context, accountID int64, keyHash string, keyCipher, keyNonce []byte) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO keys (account_id, key_hash, key_encrypted, key_nonce, created_at) VALUES (?, ?, ?, ?, ?)`,
		accountID, keyHash, keyCipher, keyNonce, nowUTC())
	if err != nil {
		if isConstraintError(err) {
			return ErrKeyExists
		}
		return err
	}
	return nil
}

// ResetKey 在同一事务内删除旧 Key 并写入新 Key：新 Key 立即生效，旧 Key 立即且永久失效，
// 历史数据不受影响。事务保证不会出现"无 Key"的中间状态。
func (s *Store) ResetKey(ctx context.Context, accountID int64, newKeyHash string, newKeyCipher, newKeyNonce []byte) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM keys WHERE account_id = ?`, accountID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO keys (account_id, key_hash, key_encrypted, key_nonce, created_at) VALUES (?, ?, ?, ?, ?)`,
		accountID, newKeyHash, newKeyCipher, newKeyNonce, nowUTC()); err != nil {
		if isConstraintError(err) {
			return ErrKeyExists
		}
		return err
	}
	return tx.Commit()
}

// GetKeyHashByAccount 返回账户当前的 Key 哈希（无 Key 时返回空串）。
func (s *Store) GetKeyHashByAccount(ctx context.Context, accountID int64) (string, error) {
	var h string
	err := s.db.QueryRowContext(ctx, `SELECT key_hash FROM keys WHERE account_id = ?`, accountID).Scan(&h)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	return h, nil
}

// GetAccountIDByKeyHash 用 Key 哈希反查账户 ID（原生客户端鉴权）。
func (s *Store) GetAccountIDByKeyHash(ctx context.Context, keyHash string) (int64, error) {
	var id int64
	err := s.db.QueryRowContext(ctx, `SELECT account_id FROM keys WHERE key_hash = ?`, keyHash).Scan(&id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, nil
		}
		return 0, err
	}
	return id, nil
}

// GetKeySecretByAccount 返回账户 Key 的加密原文与 nonce，供 Web 端重复查看。
// hasKey=false 表示账户尚无 Key；hasKey=true 且 ciphertext 为 nil 表示该 Key
// 由旧版本生成（无加密副本，无法回显，需重置）。
func (s *Store) GetKeySecretByAccount(ctx context.Context, accountID int64) (ciphertext, nonce []byte, hasKey bool, err error) {
	var ct, nn []byte
	err = s.db.QueryRowContext(ctx,
		`SELECT key_encrypted, key_nonce FROM keys WHERE account_id = ?`, accountID).Scan(&ct, &nn)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, false, nil
		}
		return nil, nil, false, err
	}
	return ct, nn, true, nil
}
