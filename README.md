# DriftClip

自托管的多平台文本粘贴板历史服务。用户在各设备上复制文本或手动输入文本后，客户端将内容上传到服务端；同一账户下的设备和 Web 端都可以查看、复制及管理这些历史记录。

第一版支持 Windows、macOS、Linux、Android、iOS 和 Web。

## 技术栈

| 模块 | 技术 |
| --- | --- |
| 服务端 | Go + SQLite |
| Web 端 | React |
| 原生客户端 | Flutter |
| 部署 | Docker Compose |

## 功能概览

- 采集并保存纯文本粘贴板内容，支持手动输入上传
- 同一账户下的全部原生客户端与 Web 端可查看远端历史
- 支持删除、筛选、复制历史记录
- 多用户，数据按账户严格隔离
- Web 使用账号密码登录；原生客户端使用 Key 访问账户历史

## 目录结构

```
server/   # Go 服务端（API + SQLite + 托管 React 静态产物）
web/      # React Web 端
client/   # Flutter 原生客户端（Windows/macOS/Linux/Android/iOS）
```

## 详细方案

见 [CLIPBOARD_SYNC_V1_PLAN.md](CLIPBOARD_SYNC_V1_PLAN.md)。

## 部署

### Docker Compose（推荐）

```bash
cd deploy
export DRIFTCLIP_SESSION_SECRET="$(openssl rand -hex 32)"
export DRIFTCLIP_KEY_PEPPER="$(openssl rand -hex 32)"
docker compose up -d --build
```

- SQLite 数据持久化在 `driftclip-data` 卷（V1 §8.1）。**备份与灾难恢复由部署者负责**（无自动备份）。
- 应用仅回环暴露 `127.0.0.1:8080`；HTTPS、域名、证书与公网反向代理由部署者负责，应用不直接暴露公网。
- 反向代理需设置 `DRIFTCLIP_SERVER_TRUSTED_PROXIES`（内网 CIDR，逗号分隔），服务端才信任其 `X-Forwarded-For` / `X-Forwarded-Proto` 头。
- `DRIFTCLIP_SERVER_REQUIRE_HTTPS=true` 已在 Compose 开启：请求必须经可信代理以 HTTPS 转发，否则被拒绝（验收 10）。
- 关闭注册：`docker compose run --rm -e DRIFTCLIP_REGISTRATION_ENABLED=false ...` 或配置挂载。

### 配置

所有配置见 [deploy/config.example.yaml](deploy/config.example.yaml)，均可被 `DRIFTCLIP_*` 环境变量覆盖。

| 关键项 | 说明 |
| --- | --- |
| `session_secret` / `key_pepper` | 必须替换为强随机值；只能由部署者安全保存，绝不入日志 |
| `history.max_history_records` | 每账户历史上限，调低重启后立即清理 |
| `history.max_clipboard_text_bytes` | 单条正文上限（默认 100 KiB） |
| `server.trusted_proxies` | 反向代理内网 CIDR；未配置时用直连地址作为客户端 IP |

### 本地开发运行

```bash
# 1. 服务端（配置已默认 goproxy.cn 镜像）
cd server && go run ./cmd/driftclip-server

# 2. Web 端（Vite dev server，/api 代理到 8080）
cd web && npm install && npm run dev   # 打开 http://localhost:5173
```

生产形态下单二进制服务同时提供 API 与 Web：

```bash
cd web && npm run build        # 产出 web/dist
cd server && go build -o driftclip-server ./cmd/driftclip-server
./driftclip-server             # 默认托管 web/dist，SPA 路由自动 fallback
```

### 客户端服务地址

原生客户端默认服务地址在打包时内置（Spec §8.1）：

```bash
cd client
flutter build macos --dart-define=DRIFTCLIP_API_BASE=https://your.domain
```

用户也可在客户端设置页修改服务地址。

## 开发环境

- Go 1.26+
- Flutter 3.44+
- Node.js 24+
