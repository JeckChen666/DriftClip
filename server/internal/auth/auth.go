// Package auth 提供密码哈希（Argon2id）、会话 token 与 Key 的生成和哈希。
//
// 安全约定：
//   - 密码用 Argon2id 哈希保存，绝不存明文；
//   - 会话 token 只存 SHA-256 哈希；
//   - Key 只存 HMAC-SHA256(key_pepper, key) 哈希，比较用 constant-time。
package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2id 参数（OWASP 推荐档：约 19 MiB 内存，交互式登录可接受）。
const (
	argon2Time    = 2
	argon2Memory  = 19456 // KiB，约 19 MiB
	argon2Threads = 1
	argon2KeyLen  = 32
	argon2SaltLen = 16
)

// HashPassword 用 Argon2id 哈希密码，返回自描述格式
// "$argon2id$v=19$m=...,t=...,p=...$<salt>$<hash>"（均为 raw base64）。
func HashPassword(password string) (string, error) {
	salt := make([]byte, argon2SaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("生成盐值: %w", err)
	}
	hash := argon2.IDKey([]byte(password), salt, argon2Time, argon2Memory, argon2Threads, argon2KeyLen)
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		argon2Memory, argon2Time, argon2Threads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash)), nil
}

// VerifyPassword 校验密码与哈希是否匹配。格式非法返回错误，不匹配返回 (false, nil)。
func VerifyPassword(password, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" {
		return false, fmt.Errorf("非法密码哈希格式")
	}
	memory, time, threads, err := parseArgon2Params(parts[3])
	if err != nil {
		return false, err
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, fmt.Errorf("非法盐值编码")
	}
	expected, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, fmt.Errorf("非法哈希编码")
	}
	actual := argon2.IDKey([]byte(password), salt, time, memory, uint8(threads), uint32(len(expected)))
	return subtle.ConstantTimeCompare(actual, expected) == 1, nil
}

func parseArgon2Params(paramStr string) (memory, time, threads uint32, err error) {
	for _, kv := range strings.Split(paramStr, ",") {
		pair := strings.SplitN(kv, "=", 2)
		if len(pair) != 2 {
			return 0, 0, 0, fmt.Errorf("非法 Argon2 参数 %q", kv)
		}
		v, perr := strconv.ParseUint(pair[1], 10, 32)
		if perr != nil {
			return 0, 0, 0, fmt.Errorf("非法 Argon2 参数 %q", kv)
		}
		switch pair[0] {
		case "m":
			memory = uint32(v)
		case "t":
			time = uint32(v)
		case "p":
			threads = uint32(v)
		}
	}
	if memory == 0 || time == 0 || threads == 0 {
		return 0, 0, 0, fmt.Errorf("Argon2 参数不完整")
	}
	return memory, time, threads, nil
}

// NewSessionToken 生成会话 token，返回原始 token（写入 Cookie）与 SHA-256 哈希（入库）。
func NewSessionToken() (token, tokenHash string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", fmt.Errorf("生成会话 token: %w", err)
	}
	token = base64.RawURLEncoding.EncodeToString(b)
	return token, HashSessionToken(token), nil
}

// HashSessionToken 计算会话 token 的 SHA-256 十六进制哈希。
func HashSessionToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// GenerateKey 生成原生客户端访问 Key：dc_ 前缀 + 32 字节 CSPRNG（raw base64url）。
// 完整 Key 只在生成/重置时返回一次，服务端只保存其哈希。
func GenerateKey() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("生成 Key: %w", err)
	}
	return "dc_" + base64.RawURLEncoding.EncodeToString(b), nil
}

// HashKey 计算 Key 的 HMAC-SHA256(key_pepper, key) 十六进制哈希。
// pepper 由部署者单独保管，即使数据库泄漏也无法直接还原 Key。
// 实际鉴权采用「哈希精确查库」：先对请求 Key 做 HMAC 得到哈希，再按唯一索引
// 在 keys 表反查账户（不比对明文 Key）。评审 F10 移除了未使用的 KeyMatches。
func HashKey(key, pepper string) string {
	mac := hmac.New(sha256.New, []byte(pepper))
	mac.Write([]byte(key))
	return hex.EncodeToString(mac.Sum(nil))
}
