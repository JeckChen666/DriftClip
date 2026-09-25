# DriftClip 开发与调试手册

三端联调指南：服务端（Go）+ Web（React）+ 原生客户端（Flutter）＋ 部署。业务时间统一 `Asia/Shanghai`（UTC+8）。

## 0. 架构与端口

| 端 | 技术 | 默认地址 |
| --- | --- | --- |
| 服务端 | Go 1.26 + SQLite（WAL） | `127.0.0.1:8080`（`/api/*`） |
| Web | React + Vite | `localhost:5173`（开发，`/api` 代理到 8080） |
| 客户端 | Flutter（macOS/iOS/Android/Windows/Linux） | 原生窗口 |
| 部署 | Docker Compose / 单二进制 | `127.0.0.1:8080`（回环，对外走反向代理） |

## 1. 环境准备（本机已验证）

| 工具链 | 状态 | 备注 |
| --- | --- | --- |
| Go 1.26.5 | ✅ | 依赖走 `goproxy.cn`（已配置，GFW 下勿改回默认源） |
| Node 24 + npm | ✅ | Flutter pub 可直连 |
| Flutter 3.44.8 | ✅ | |
| Xcode 26.6 + CocoaPods | ✅ | 见「常见问题」：App Store 对 Intel 会错发 Apple Silicon 版，需官网 Universal xip |
| Docker 29.6.2 | ✅ | 引擎可运行（desktop-linux） |
| Android SDK | ❌ | 未装；跑 Android 端前需先装 |

## 2. 服务端（Go）调试

```bash
cd server
go run ./cmd/driftclip-server            # 启动，监听 0.0.0.0:8080
go test ./...                            # 全部测试（含验收 1/2/3/4/6/10 集成用例）
go vet ./...                             # 静态检查
```

- **配置**：`deploy/config.example.yaml` 或 `DRIFTCLIP_*` 环境变量（见 `server/internal/config`）。常用：`DRIFTCLIP_DATABASE_PATH`、`DRIFTCLIP_SERVER_LISTEN_ADDR`、`DRIFTCLIP_SERVER_REQUIRE_HTTPS`。
- **日志**：`log/slog` 输出到 stdout（`http_request` 记录方法与状态码；不记录 Key/密码/正文）。
- **冒烟**：
  ```bash
  curl -X POST http://127.0.0.1:8080/api/v1/auth/register \
    -H 'Content-Type: application/json' -d '{"email":"a@b.com","password":"pw"}'
  ```
- **集成测试**：`server/internal/handler/integration_test.go` 用真实临时 SQLite，覆盖账户隔离、保留策略、Key 生命周期、拒绝语义等核心验收项。

## 3. Web 端（React）调试

```bash
cd web
npm install
npm run dev        # 打开 http://localhost:5173（需服务端已启动，/api 由 Vite 代理到 8080）
```

- **构建**：`npm run build` → 产物 `web/dist`（由 Go 服务托管，单二进制交付）。
- **组件测试**：`npm test`（Vitest + Testing Library，13 个用例）。
- **端到端（Playwright，真实浏览器）**：先起服务端 + `npm run dev`，再：
  ```bash
  node scripts/e2e-p02.mjs   # 核心闭环：注册→Key→上传→列表→详情→删除
  node scripts/e2e-p04.mjs   # 增强：筛选→批量删除→清空 5s 确认
  ```
  E2E 截图输出到仓库根 `output/e2e/P0X-e2e/`（已被 gitignore）。
- **调试**：浏览器 DevTools；Vite HMR 即时刷新。CSRF 契约：所有状态修改请求需带 `X-Requested-With: XMLHttpRequest`（`src/lib/api.ts` 已自动处理）。

## 4. 客户端（Flutter）调试

### 运行（macOS，debug 模式）

```bash
cd client
flutter run -d macos          # 默认 debug：JIT + 热重载
```

运行期快捷键：`r` 热重载 · `R` 热重启 · `q` 退出。

### 其他模式与构建

```bash
flutter run -d macos --release        # 正式性能模式（AOT）
flutter build macos --debug           # 仅构建 debug app，不进入交互会话
flutter build macos --release         # 构建发布包
flutter test                          # 单元/Widget 测试（46 个用例）
flutter analyze                       # 静态检查
```

### Android 签名

Release APK 的签名配置在 `client/android/app/build.gradle.kts`：优先读环境变量
（CI 注入 secrets），其次读 `client/android/key.properties`（已被 .gitignore 忽略），
两者都缺失时回退 debug 签名（仅供本地验证，不可用于发布）。

本地生成正式签名密钥（只做一次，妥善保管，**不要提交进仓库**）：

```bash
keytool -genkey -v -keystore ~/driftclip-release.keystore.jks \
  -alias driftclip -keyalg RSA -keysize 2048 -validity 10000
```

本地构建（任选一种方式提供密钥）：

```bash
# 方式一：key.properties
cat > client/android/key.properties <<'EOF'
storeFile=/Users/you/driftclip-release.keystore.jks
storePassword=你的store密码
keyAlias=driftclip
keyPassword=你的key密码
EOF

# 方式二：环境变量
export DRIFTCLIP_ANDROID_KEYSTORE_PATH=~/driftclip-release.keystore.jks
export DRIFTCLIP_ANDROID_KEYSTORE_PASSWORD=...
export DRIFTCLIP_ANDROID_KEY_ALIAS=driftclip
export DRIFTCLIP_ANDROID_KEY_PASSWORD=...
```

CI（release.yml 的 android job）从仓库 secrets 读取，需配置四项：
`ANDROID_KEYSTORE_BASE64`（keystore 文件的 base64）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。未配置时构建仍会成功但回退 debug
签名，并在构建摘要中提示。

### 服务地址

默认 `http://127.0.0.1:8080`。打包时内置远程地址：

```bash
flutter build macos --dart-define=DRIFTCLIP_API_BASE=https://your.domain
```

用户也可在客户端「设置」页临时修改。

### 平台约束

| 目标 | 本机可构建？ | 备注 |
| --- | --- | --- |
| macOS 桌面 | ✅ | 已验证 |
| iOS | ✅ | Xcode 已含 iOS SDK；真机需 Apple ID 签名 |
| Android | ❌ | 需装 Android SDK |
| Windows / Linux 桌面 | ❌ | Flutter 不支持 Mac 交叉构建，需对应平台或 CI |

### 真机验收清单（ROADMAP 自动化未覆盖项）

P0–P3 改进（docs/ROADMAP.md）中依赖真实设备/系统的验收项：

| # | 项目 | 步骤 | 预期 |
| --- | --- | --- | --- |
| 1 | Android release 联网 | 安装 release APK → 配置服务端 | 能同步历史（此前 release 包缺 INTERNET 权限，完全断网） |
| 2 | Android/iOS 明文 HTTP | 连接 `http://内网IP:8080` | 可用（此前被系统静默拦截） |
| 3 | Android 扫码导入 | Web「Key 管理」页展示二维码 → 客户端「扫码导入」 | 自动填入服务地址与 Key，保存连通 |
| 4 | iOS 相机权限 | 首次扫码导入 | 弹出相机用途说明（NSCameraUsageDescription） |
| 5 | macOS 托盘常驻 | 启动应用 → 关闭主窗口 | ✅ 托盘图标已本机截图验证（2026-09-26）；关闭主窗口后进程常驻、复制仍入库仍需手动确认 |
| 6 | macOS 登录项 | 设置开启「登录自启动」→ 系统设置→通用→登录项 | 出现 DriftClip；重启后自动启动并恢复监听 |
| 7 | Windows/Linux 托盘与自启动 | 同 5/6 | 关窗最小化到托盘；注册表/.desktop 生效 |
| 8 | 断网补传 | 断网复制 3 条 → 恢复网络 | 界面/托盘显示「待同步」，恢复后按序补传 |
| 9 | 服务端限流 | 同一 IP 连续登录失败 >10 次/分 | 第 11 次返回 429（自动化已覆盖，真机复核网关行为） |
| 10 | Web 连接引导 | 注册 → Key 管理页生成 Key | 出现下载链接、服务地址与二维码；扫码/复制可用 |

## 5. 部署调试

### Docker Compose

```bash
cd deploy
export DRIFTCLIP_SESSION_SECRET="$(openssl rand -hex 32)"
export DRIFTCLIP_KEY_PEPPER="$(openssl rand -hex 32)"
docker compose up -d --build
```

### 单二进制（无需 Docker，本地验证）

```bash
cd web && npm run build                 # 产出 web/dist
cd server && go build -o driftclip-server ./cmd/driftclip-server
./driftclip-server                      # 默认托管 web/dist，SPA 路由自动 fallback
```

单二进制验证：`GET /` 返回 React 页面、`GET /api/v1/auth/me` 返回 401、`GET /keys` SPA fallback 200。

## 6. 端到端启动顺序

1. 起服务端：`cd server && go run ./cmd/driftclip-server`
2. 起 Web：`cd web && npm run dev`，浏览器打开 5173
3. Web 注册账号 → 登录 → 生成 Key（完整 Key 只展示一次，妥善保存）
4. 跑客户端：`cd client && flutter run -d macos`，填入服务地址与 Key
5. 客户端手动输入或开启剪贴板监听上传 → 三端均可查看/删除/筛选同一账户历史

## 7. 常见问题排查

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| `xcodebuild: bad CPU type in executable` | App Store 给 Intel Mac 错发 Apple Silicon 版 Xcode | 到 [developer.apple.com/download/all](https://developer.apple.com/download/all/) 下载 `Xcode_26.6_Universal.xip` 解压安装 |
| Go 拉包超时 | GFW 默认源不可达 | `go env -w GOPROXY=https://goproxy.cn,direct`（本机已配置） |
| Web 页 `401 未登录` | 服务端未启动或会话过期 | 先起服务端；重新登录 |
| `flutter run -d macos` 报缺 Xcode | Xcode 未装/未切到 Xcode | 装 Universal 版后 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 客户端连不上服务端 | 服务地址不对或服务端未起 | 检查服务端；在设置页改服务地址 |
| `docker compose` 启动后访问 400 | `require_https=true` 需经反向代理 HTTPS 转发 | 配置可信代理；本地验证可临时设 `DRIFTCLIP_SERVER_REQUIRE_HTTPS=false` |
