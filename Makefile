# DriftClip 设计令牌 / 构建工具入口

.PHONY: tokens tokens-check client web test all

# 同步设计令牌（Flutter _palette.g.dart + Web tokens.generated.css）
tokens:
	dart run tool/sync_tokens.dart

# 校验当前生成文件与 tokens.json 一致；CI/提交前使用
tokens-check:
	dart run tool/sync_tokens.dart --check

# Flutter 客户端
client:
	cd client && flutter analyze

# Web 前端
web:
	cd web && npm install && npm run build

# 跑全部
all: tokens-check client web

test:
	cd web && npm test
