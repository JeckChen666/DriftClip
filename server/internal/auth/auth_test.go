package auth

import (
	"strings"
	"testing"
)

func TestHashAndVerifyPassword(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$") {
		t.Fatalf("哈希格式不正确: %q", hash)
	}
	// 正确密码通过
	if ok, err := VerifyPassword("correct horse battery staple", hash); err != nil || !ok {
		t.Fatalf("正确密码应通过校验: ok=%v err=%v", ok, err)
	}
	// 错误密码失败
	if ok, _ := VerifyPassword("wrong password", hash); ok {
		t.Fatal("错误密码不应通过")
	}
	// 非法格式报错
	if _, err := VerifyPassword("x", "not-a-hash"); err == nil {
		t.Fatal("非法哈希格式应报错")
	}
}

func TestGenerateKeyFormat(t *testing.T) {
	k, err := GenerateKey()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(k, "dc_") {
		t.Fatalf("Key 应以 dc_ 开头: %q", k)
	}
	// dc_ + 32 字节 raw base64url（43 字符）=> 总长 46
	if len(k) != 46 {
		t.Fatalf("Key 长度应为 46，实际 %d (%q)", len(k), k)
	}
	k2, _ := GenerateKey()
	if k == k2 {
		t.Fatal("两次生成的 Key 不应相同")
	}
}

func TestHashKeyDeterministicAndPepperSensitive(t *testing.T) {
	const key = "dc_abc"
	h1 := HashKey(key, "pepper-A")
	h2 := HashKey(key, "pepper-A")
	if h1 != h2 {
		t.Fatal("相同 Key 与 pepper 应得到相同哈希")
	}
	h3 := HashKey(key, "pepper-B")
	if h1 == h3 {
		t.Fatal("不同 pepper 应得到不同哈希")
	}
	if HashKey("dc_xxx", "pepper-A") == h1 {
		t.Fatal("错误 Key 应得到不同哈希")
	}
}

func TestSessionTokenHashing(t *testing.T) {
	tok, tokHash, err := NewSessionToken()
	if err != nil {
		t.Fatal(err)
	}
	if HashSessionToken(tok) != tokHash {
		t.Fatal("会话 token 哈希不一致")
	}
	tok2, _, _ := NewSessionToken()
	if tok == tok2 {
		t.Fatal("两次生成的会话 token 不应相同")
	}
}

func TestKeyEncryptDecryptRoundtrip(t *testing.T) {
	key := "dc_0123456789abcdefABCDEF"
	cipher, nonce, err := EncryptKey(key, "pepper-A")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(cipher), key) {
		t.Fatal("密文不应包含明文 Key")
	}
	got, err := DecryptKey(cipher, nonce, "pepper-A")
	if err != nil {
		t.Fatal(err)
	}
	if got != key {
		t.Fatalf("解密应还原原文，实际 %q", got)
	}
}

func TestKeyDecryptWrongPepperFails(t *testing.T) {
	cipher, nonce, err := EncryptKey("dc_secret", "pepper-A")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := DecryptKey(cipher, nonce, "pepper-B"); err == nil {
		t.Fatal("错误 pepper 应解密失败（GCM 认证）")
	}
}

func TestKeyEncryptNonceUnique(t *testing.T) {
	_, n1, err := EncryptKey("dc_same", "pepper")
	if err != nil {
		t.Fatal(err)
	}
	_, n2, err := EncryptKey("dc_same", "pepper")
	if err != nil {
		t.Fatal(err)
	}
	if string(n1) == string(n2) {
		t.Fatal("两次加密的 nonce 不应相同")
	}
}
