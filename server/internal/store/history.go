package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
)

type History struct {
	ID             int64
	AccountID      int64
	Content        string
	Source         string
	ReceivedAt     time.Time
	PublicIP       string
	Platform       string
	OSVersion      string
	DeviceModel    string
	AppVersion     string
	InstallationID string
}

// HistoryListItem 是列表投影：正文只含前 500 字符预览，不含完整正文与公网 IP。
// （Spec 工程默认实践：列表不返回大体积字段，详情接口才返回全文与完整 IP。）
type HistoryListItem struct {
	ID             int64
	ContentPreview string
	Source         string
	ReceivedAt     time.Time
	Platform       string
	OSVersion      string
	DeviceModel    string
	AppVersion     string
	InstallationID string
}

type NewHistory struct {
	Content, Source, PublicIP, Platform string
	OSVersion, DeviceModel, AppVersion, InstallationID string
}

// ListFilter 是历史列表的组合筛选条件，条件之间为 AND 关系。
// Query 为正文子串（忽略英文字母大小写）；From/To 为 RFC3339 UTC（闭区间）。
type ListFilter struct {
	Platform string
	Query    string
	From     string
	To       string
	Limit    int
	Offset   int
}

// deleteOverflowSQL 保留策略：删除某账户除最新 MaxHistoryRecords 条外的所有旧记录。
// 以 (received_at DESC, id DESC) 排序后 OFFSET N 取其余部分，LIMIT -1 表示不限条数。
// 该子查询与 idx_history_account_time 索引匹配，避免全表扫描。
const deleteOverflowSQL = `DELETE FROM history WHERE account_id = ? AND id IN (
  SELECT id FROM history WHERE account_id = ?
  ORDER BY received_at DESC, id DESC
  LIMIT -1 OFFSET ?)`

// CreateHistory 写入一条记录，并在同一事务内执行保留策略：
// 插入后立即删除该账户超出上限的最旧记录（按 received_at + id）。
// 事务保证"写入与淘汰"原子完成，中断时不会留下超限状态。
func (s *Store) CreateHistory(ctx context.Context, accountID int64, in NewHistory) (*History, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// 同一时间戳同时用于写入与返回，保证上传响应的 received_at 与后续读回一致（评审 F9）。
	receivedAt := nowUTC()
	res, err := tx.ExecContext(ctx,
		`INSERT INTO history (account_id, content, source, received_at, public_ip, platform,
		    os_version, device_model, app_version, installation_id)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, in.Content, in.Source, receivedAt, in.PublicIP, in.Platform,
		in.OSVersion, in.DeviceModel, in.AppVersion, in.InstallationID)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()

	if _, err := tx.ExecContext(ctx, deleteOverflowSQL, accountID, accountID, s.MaxHistoryRecords); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	parsed, _ := time.Parse(time.RFC3339, receivedAt)
	return &History{
		ID: id, AccountID: accountID, Content: in.Content, Source: in.Source,
		ReceivedAt: parsed, PublicIP: in.PublicIP, Platform: in.Platform,
		OSVersion: in.OSVersion, DeviceModel: in.DeviceModel,
		AppVersion: in.AppVersion, InstallationID: in.InstallationID,
	}, nil
}

func (s *Store) GetHistory(ctx context.Context, accountID, id int64) (*History, error) {
	var h History
	var receivedAt string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, content, source, received_at, public_ip, platform,
		    COALESCE(os_version,''), COALESCE(device_model,''),
		    COALESCE(app_version,''), COALESCE(installation_id,'')
		 FROM history WHERE id = ? AND account_id = ?`, id, accountID).
		Scan(&h.ID, &h.AccountID, &h.Content, &h.Source, &receivedAt, &h.PublicIP, &h.Platform,
			&h.OSVersion, &h.DeviceModel, &h.AppVersion, &h.InstallationID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	t, err := time.Parse(time.RFC3339, receivedAt)
	if err != nil {
		return nil, err
	}
	h.ReceivedAt = t
	return &h, nil
}

func (s *Store) ListHistory(ctx context.Context, accountID int64, f ListFilter) ([]HistoryListItem, error) {
	q := `SELECT id, substr(content, 1, 500), source, received_at, platform,
	      COALESCE(os_version,''), COALESCE(device_model,''),
	      COALESCE(app_version,''), COALESCE(installation_id,'')
	      FROM history WHERE account_id = ?`
	args := []any{accountID}
	q, args = appendHistoryWhere(q, args, f)
	q += ` ORDER BY received_at DESC, id DESC LIMIT ? OFFSET ?`
	args = append(args, f.Limit, f.Offset)

	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []HistoryListItem
	for rows.Next() {
		var it HistoryListItem
		var receivedAt string
		if err := rows.Scan(&it.ID, &it.ContentPreview, &it.Source, &receivedAt, &it.Platform,
			&it.OSVersion, &it.DeviceModel, &it.AppVersion, &it.InstallationID); err != nil {
			return nil, err
		}
		t, err := time.Parse(time.RFC3339, receivedAt)
		if err != nil {
			return nil, err
		}
		it.ReceivedAt = t
		items = append(items, it)
	}
	return items, rows.Err()
}

func (s *Store) CountHistory(ctx context.Context, accountID int64, f ListFilter) (int, error) {
	q := `SELECT COUNT(*) FROM history WHERE account_id = ?`
	args := []any{accountID}
	q, args = appendHistoryWhere(q, args, f)
	var n int
	if err := s.db.QueryRowContext(ctx, q, args...).Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

// DeleteHistory 删除单条记录，返回是否确实删除了（他人资源或不存在返回 false）。
func (s *Store) DeleteHistory(ctx context.Context, accountID, id int64) (bool, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM history WHERE id = ? AND account_id = ?`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// DeleteHistories 批量删除，返回实际删除条数。account_id 过滤保证不越权删除他人记录。
func (s *Store) DeleteHistories(ctx context.Context, accountID int64, ids []int64) (int64, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(ids)), ",")
	args := make([]any, 0, len(ids)+1)
	args = append(args, accountID)
	for _, id := range ids {
		args = append(args, id)
	}
	res, err := s.db.ExecContext(ctx,
		`DELETE FROM history WHERE account_id = ? AND id IN (`+placeholders+`)`, args...)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

func (s *Store) ClearHistory(ctx context.Context, accountID int64) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM history WHERE account_id = ?`, accountID)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// appendHistoryWhere 追加组合筛选条件（AND 关系）并返回扩展后的 SQL 与参数。
// 所有条件参数化，正文模糊查询显式转义 LIKE 通配符，避免 SQL 注入与通配符误配。
func appendHistoryWhere(q string, args []any, f ListFilter) (string, []any) {
	if f.Platform != "" {
		q += ` AND platform = ?`
		args = append(args, f.Platform)
	}
	if f.Query != "" {
		q += ` AND LOWER(content) LIKE ? ESCAPE '\'`
		args = append(args, "%"+escapeLike(strings.ToLower(f.Query))+"%")
	}
	if f.From != "" {
		q += ` AND received_at >= ?`
		args = append(args, f.From)
	}
	if f.To != "" {
		q += ` AND received_at <= ?`
		args = append(args, f.To)
	}
	return q, args
}

// escapeLike 转义 LIKE 通配符与转义符本身（配合 ESCAPE '\' 使用）。
func escapeLike(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(s)
}
