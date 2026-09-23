# 贡献指南（DriftClip）

感谢你愿意为 DriftClip 出力！

## 上手

DriftClip 是一个包含三端的 monorepo：

| 组件 | 路径 | 工具链 |
| --- | --- | --- |
| 服务端 | `server/` | Go 1.26+ |
| Web 端 | `web/` | Node.js 24+ |
| 原生客户端 | `client/` | Flutter 3.44+ |

本地跑起整套环境：

```bash
# 服务端 — API 在 http://127.0.0.1:8080
cd server && go run ./cmd/driftclip-server

# Web — dev server 在 http://localhost:5173（/api 代理到 :8080）
cd web && npm install && npm run dev

# 原生客户端（以 macOS 为例）
cd client && flutter run -d macos
```

端口、常见问题排查、E2E 流程等见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 提 PR 之前

CI 跑的检查你本地都能跑，请先确认通过：

```bash
cd server && go vet ./... && go test ./...
cd web && npm run lint && npm test
cd client && flutter analyze && flutter test
```

约定：

- 改动保持聚焦，一个 PR 只做一件事
- 服务端新行为需要配套测试（参考 `server/internal/handler/integration_test.go` 的写法）
- UI 改动请遵循共享设计令牌（`tokens/tokens.json`）
- 提交信息用约定式风格（`feat:`、`fix:`、`docs:` …），中英文均可

## 报 bug / 提需求

用 bug 或 feature 模板开 issue，并尽量填全信息——对这种多端应用，平台、版本号、复现步骤尤其重要。

## 安全问题

安全问题请勿开公开 issue，见 [SECURITY.md](SECURITY.md)。
