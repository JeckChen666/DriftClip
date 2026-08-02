package store

import (
	"strings"
)

// isConstraintError 判断错误是否为唯一约束冲突。
// 统一由上层映射为 ErrDuplicateEmail / ErrKeyExists，避免依赖具体驱动错误字符串。
func isConstraintError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "UNIQUE constraint failed") ||
		strings.Contains(msg, "constraint failed")
}
