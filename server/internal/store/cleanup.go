package store

import (
	"context"
)

// CleanupAccounts 将每个账户的历史清理到配置上限内（保留最新 MaxHistoryRecords 条）。
// 用于服务启动阶段（应对配置上限被调低）以及上传成功后的保留执行。
// 逐账户执行，单条语句原子完成，失败可安全重试。
func (s *Store) CleanupAccounts(ctx context.Context) (int64, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT DISTINCT account_id FROM history`)
	if err != nil {
		return 0, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	var total int64
	for _, id := range ids {
		res, err := s.db.ExecContext(ctx, deleteOverflowSQL, id, id, s.MaxHistoryRecords)
		if err != nil {
			return total, err
		}
		n, _ := res.RowsAffected()
		total += n
	}
	return total, nil
}
