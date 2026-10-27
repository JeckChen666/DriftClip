# DriftClip 功能提炼与重建规格

> **文档用途**：完整提炼现有 DriftClip 项目的功能点、数据契约与产品规则，作为「重做一版（性能更好、外观更好）」的唯一依据。
>
> **事实来源**：本规格中的服务端部分（API、数据模型、鉴权、限流、保留策略）由 `server/` 源码逐行核对得出；Web 与客户端部分基于 `web/src`、`client/lib` 全量阅读。所有"已实现"结论均可在文中给出的文件位置复核。
>
> **原始业务规格**：完整的产品设计意图见 [`CLIPBOARD_SYNC_V1_PLAN.md`](./CLIPBOARD_SYNC_V1_PLAN.md)，历史改进记录见 [`ROADMAP.md`](./ROADMAP.md)。本文档描述的是**代码实际状态**，两者存在差异处已在 §9 标注。

---

## 目录

1. [产品定位与核心闭环](#1-产品定位与核心闭环)
2. [系统架构](#2-系统架构)
3. [功能点总览](#3-功能点总览)
4. [功能点明细 — 服务端](#4-功能点明细--服务端)
5. [功能点明细 — Web 端](#5-功能点明细--web-端)
6. [功能点明细 — 原生客户端](#6-功能点明细--原生客户端)
7. [数据模型与 API 契约](#7-数据模型与-api-契约)
8. [产品规则与不变量（重建必须保留）](#8-产品规则与不变量重建必须保留)
9. [已确认的实现缺陷](#9-已确认的实现缺陷)
10. [重建建议：性能](#10-重建建议性能)
11. [重建建议：外观](#11-重建建议外观)
12. [重建建议：架构与范围](#12-重建建议架构与范围)

---

## 1. 产品定位与核心闭环

**一句话**：自托管的多平台**纯文本剪贴板历史**服务 —— 在 A 设备复制，在 B 设备找回。

| 维度 | 内容 |
| --- | --- |
| 形态 | 单 Go 二进制 + SQLite，托管 React 静态站点，无外部服务依赖 |
| 部署 | Docker Compose / 单二进制，默认监听 `127.0.0.1:8080`，公网需自备反向代理 + HTTPS |
| 多租户 | 邮箱+密码账户体系，数据按 `account_id` 严格隔离 |
| 数据类型 | **仅纯文本**（设计取舍，不支持富文本/图片/文件） |
| 保留策略 | 每账户滚动保留最新 N 条（默认 1000），单条上限 100 KiB |
| 平台 | Web + Windows / macOS / Linux / Android / iOS |
| 开源 | MIT，仓库 `github.com/JeckChen666/DriftClip` |

### 核心闭环（用户价值链）

```
① 设备配置：安装客户端 → 输入服务地址 + API Key
② 采集：配置后显式开启「剪贴板监听」→ 复制内容
③ 上传：客户端去重校验 → POST /history → 服务端写入并执行保留淘汰
④ 取回：任意端登录/联网 → 搜索历史 → 复制回本机剪贴板
⑤ 管理：筛选、删除、批量删除、清空、改密、Key 管理
```

---

## 2. 系统架构

| 端 | 技术栈 | 职责 |
| --- | --- | --- |
| `server/` | Go 1.26 + SQLite（WAL，modernc 驱动） | REST API、鉴权、限流、保留策略、托管 Web 产物 |
| `web/` | React 19 + Vite 8 + TypeScript + Tailwind 3 + Radix | 浏览器端历史浏览与管理 |
| `client/` | Flutter（5 平台） | 剪贴板监听采集、上传、历史浏览、桌面常驻 |
| `deploy/` | Dockerfile + Compose + config.example.yaml | 交付与配置 |

**中间件顺序**（`server/internal/handler/router.go:41-46`，外→内）：
`请求日志 → HTTPS 强制 → CSRF 校验 → 路由级鉴权`

**共享设计令牌**（重要的工程资产）：`tokens/tokens.json` 是唯一真源，由 `tool/sync_tokens.dart` 生成 `web/src/tokens.generated.css` 与 `client/lib/theme/_palette.g.dart`，两端视觉与客户端色彩完全同步。**重建时建议保留此机制。**

---

## 3. 功能点总览

| # | 功能域 | 服务端 | Web | 客户端 |
| --- | --- | :-: | :-: | :-: |
| F1 | 账户注册 / 登录 / 登出 / 改密 | ✅ | ✅ | — |
| F2 | 会话管理（Cookie） | ✅ | ✅ | — |
| F3 | API Key 生成 / 回显 / 重置 | ✅ | ✅ | — |
| F4 | 剪贴板自动采集 | — | — | ✅ |
| F5 | 手动输入上传 | 接受 | — | ✅ |
| F6 | 历史上传 API | ✅ | — | ✅ |
| F7 | 历史列表 / 筛选 / 搜索 / 分页 | ✅ | ✅ | ✅（仅本地筛选） |
| F8 | 历史详情查看 | ✅ | ✅ | ✅ |
| F9 | 复制到本机剪贴板 | — | ✅ | ✅ |
| F10 | 单条 / 批量 / 清空删除 | ✅ | ✅ | ✅ |
| F11 | 保留策略（每账户 N 条） | ✅ | 展示 | — |
| F12 | 限流（注册登录 / 上传） | ✅ | — | 401/413 处理 |
| F13 | HTTPS 强制 + 可信代理 | ✅ | — | — |
| F14 | 设备元数据采集上报 | 存储 | 展示 | ✅ |
| F15 | 客户端去重 | 仅客户端执行 | — | ✅ |
| F16 | 桌面托盘常驻 | — | — | ✅ |
| F17 | 登录自启动 | — | — | ✅ |
| F18 | 离线上传队列 | — | — | ⚠️ **已实现但未接线** |
| F19 | 同步状态可视化 | — | — | ✅（依赖 F18） |
| F20 | 连接配置引导（二维码/深链） | — | ✅ | ✅（扫码/剪贴板导入） |
| F21 | 连接校验与 meta 协商 | `GET /meta` | — | ✅ |
| F22 | 自动刷新 | — | ✅（可选） | ⚠️ 固定 3s 全量 |
| F23 | 限流开关 / 注册开关 / 参数热配 | ✅ | — | — |

---

## 4. 功能点明细 — 服务端

### 4.1 鉴权体系（双轨）

| 调用方 | 凭据 | 可执行操作 |
| --- | --- | --- |
| Web | `driftclip_session` Cookie（`HttpOnly`/`SameSite=Lax`/生产 `Secure`） | 全部历史读删 + Key 管理 + 改密 + 登出 |
| 原生客户端 | `Authorization: Bearer <Key>` | 全部历史读删 + **上传** |

关键约束（`router.go:9-16` 注释明确）：
- **上传 `POST /history` 仅接受 Key**（`RequireKey`），Web 会话不能写入。
- 历史查看/详情/删除/批量/清空为 `RequireAnyAuth`，两种凭据皆可。
- Key **不能**登录 Web、不能管理 Key、不能改密。

**密码学实现**（`server/internal/auth/`）：
- 密码：Argon2id 哈希
- 会话：`SHA-256(token)` 存库，库中无明文
- Key 鉴权：`HMAC-SHA256(key_pepper, key)` 存 `key_hash`
- Key 回显：另存 `AES-256-GCM` 密文 + nonce（密钥由 `key_pepper` 域分离派生）→ **支持随时回显**（旧版生成的 Key 无密文副本，回显返回 409）

### 4.2 CSRF 与 HTTPS

- **CSRF**（`middleware.go:124-149`）：非 GET/HEAD/OPTIONS 且携带会话 Cookie 时，必须带 `X-Requested-With: XMLHttpRequest`。注册/登录豁免。二重防护叠加 `SameSite=Lax`。
- **HTTPS**（`middleware.go:100-117`）：`require_https=true` 时，直连 TLS 或来自 `trusted_proxies` CIDR 的 `X-Forwarded-Proto: https` 才放行，否则 400。
- **公网 IP**（`clientIP`）：仅信任配置内的反向代理的转发头，否则用直连地址；**不接受客户端提交的 IP**。

### 4.3 限流

内存滑动窗口（`middleware/ratelimit.go`），单进程计数，4096 key 上限防内存膨胀：

| 端点 | 维度 | 默认 | 超限 |
| --- | --- | --- | --- |
| 注册 / 登录 | 来源 IP | 10 次 / 60s | 429 + `Retry-After: 60` |
| 上传 | 账户 | 120 次 / 60s | 429 + `Retry-After: 60` |

上传限流器挂在鉴权**之后**，从 context 取 `account_id` 作为键。

### 4.4 保留策略

- 写入与淘汰在**同一事务**内完成，中断不残留超限状态（`store/history.go:66-99`）。
- 淘汰 SQL 匹配 `(account_id, received_at DESC, id DESC)` 复合索引，避免全表扫描。
- 服务启动时执行 `CleanupAccounts()`，把每个账户清理到当前上限（应对配置调低）。
- 调高上限**不恢复**已删数据。

### 4.5 上传校验链（`handler/history.go:38-91`）

按顺序：JSON 解析 → 正文非空 → 字节数 ≤ 上限（超限 413）→ 合法 UTF-8 → `source ∈ {clipboard, manual}` → manual 需非纯空白 → `platform ∈ {windows,macos,linux,android,ios}` → 写入 → 事务内淘汰。

**任何失败都返回明确错误，不静默截断、不静默丢弃。**

### 4.6 错误与日志规范

- 统一错误体 `{"error": "<中文信息>"}`，不泄漏内部细节。
- 登录失败统一返回「邮箱或密码错误」，**不区分邮箱是否存在**（防账户枚举）。
- 请求日志只记录 method / path / status / dur_ms；**Key、密码、会话、正文一律不入日志**。
- 越权访问他人记录返回 **404 而非 403**（不泄漏存在性）。

### 4.7 静态托管

托管 `web/dist`，SPA 路由自动 fallback 到 `index.html`（`/keys`、`/settings` 直连返回 200）。

---

## 5. 功能点明细 — Web 端

### 5.1 路由与导航

| 路由 | 页面 | 鉴权 | 标题 |
| --- | --- | :-: | --- |
| `/login` | 登录 | 公开 | 登录 DriftClip |
| `/register` | 注册 | 公开 | 注册 DriftClip |
| `/` | 历史 | 需登录 | 历史 |
| `/keys` | Key 管理 | 需登录 | Key 管理 |
| `/settings` | 设置 | 需登录 | 设置 |
| `*` | 重定向 `/` | — | **无 404 页** |

布局为**顶部导航栏**（无侧边栏）：Logo / 历史 / Key 管理 / 设置 / 当前邮箱 / 退出。内容区固定 `max-w-960px`。每页页脚含 GitHub 仓库链接。

### 5.2 历史页（核心屏）

| 能力 | 实现细节 |
| --- | --- |
| 列表 | 服务端分页，`PAGE_SIZE = 20` 固定 |
| 平台筛选 | Select：全部 / windows / macos / linux / android / ios（**直接展示原始 key，无中文化**） |
| 文本搜索 | 输入框 `q`，服务端子串匹配（英文忽略大小写） |
| 时间范围 | 两个 `datetime-local`（from / to），**仅有 aria-label，无可见标签** |
| 组合逻辑 | 全部 **AND**；需点「应用」才生效 |
| 排序 | **无排序功能** |
| 分页 | 仅上一页 / 下一页 + 页码，**无跳页、无每页条数** |
| 多选 | 逐行复选框 + 「全选」（**仅选当前页**）+「删除所选 (N)」 |
| 单条删除 | 行内垃圾桶图标，**无二次确认、无撤销** |
| 清空全部 | 按钮内 5 秒倒计时 → 「确认清空全部」 |
| 复制 | 行内复制图标；因列表只有 500 字预览，**先请求详情再复制全文** |
| 详情 | 行内展开，`<pre>` 全文 + `<dl>` 元信息网格；**同时只展开一条** |
| 刷新 | 手动刷新 + 自动刷新下拉（关闭/5s/30s/1min/5min，存 localStorage） |
| 加载态 | 仅首屏显示 4 个骨架卡片；翻页/筛选时旧列表**原地停留无指示** |
| 空态 | 「暂无历史记录」—— **与"筛选无结果"共用同一文案** |
| 错误态 | 单条 destructive Alert 承载所有错误 |
| 响应式 | 仅筛选栏宽度自适应；**无移动端专属布局**，无表格/紧凑模式 |
| 键盘快捷键 | **完全没有** |

### 5.3 Key 管理页

| 能力 | 实现细节 |
| --- | --- |
| 状态 | `GET /keys` → `has_key`；绿色盾牌徽标「Key 状态：已启用」 |
| 生成 | 仅无 Key 时显示；已有 Key 再生成返回 409 |
| 回显 | 「查看 Key」→ `GET /keys/secret`（**支持重复查看**，AES 加密存储） |
| 重置 | 5 秒倒计时按钮；新 Key 立即生效，旧 Key 永久失效，历史保留 |
| 复制 | 一键复制完整 Key |
| 展示样式 | 琥珀色代码块 `select-all`；**无自动隐藏计时器** |
| 连接引导 | 仅在 Key 可见时渲染 `ConnectGuide` |

**ConnectGuide 内容**：
- 二维码编码 `driftclip://connect?server=<url>&key=<key>`（`qrcode` 库主线程生成 base64 PNG）
- GitHub Releases 下载链接
- 4 步图文引导
- 「复制完整配置」

### 5.4 设置页

仅两项：**修改密码**（需当前密码，成功后跳回登录页）+ **退出登录**。

> 无：主题偏好、语言、自动刷新设置、数据导出、设备列表、账户删除、通知设置。

### 5.5 登录 / 注册

- 邮箱 + 密码两个字段，**纯原生 HTML 校验**，无强度提示、无确认密码、无忘记密码、无邮箱验证。
- 注册成功直接跳转 `/keys`（引导生成 Key）。
- 会话：挂载时 `GET /auth/me` 探测，邮箱仅存内存。
- CSRF：所有非 GET 请求自动带 `X-Requested-With: XMLHttpRequest`。

### 5.6 设计系统

- **技术**：Tailwind 3.4.19 + Radix + lucide-react，**中文界面**。
- **令牌**：CSS 变量 → Tailwind `color-mix()` 包装以支持透明度修饰符。
- **深色模式**：已实现（`darkMode: 'media'` + 完整深色调色板），**但无手动切换开关**。
- **组件**：10 个基础件（button/card/input/select/checkbox/label/badge/alert/skeleton/toast）。
- **已装未用**：`react-dialog`、`react-dropdown-menu`、`react-separator`、`react-switch`、`react-tooltip`、`playwright`（无配置无用例）→ **实际没有弹窗组件**，两个破坏性流程都是按钮内联状态。
- **闲置令牌**：`--platform-*` 七种平台色、`--status-*`、`--radius-pill` 等已生成但**从未被引用**。

---

## 6. 功能点明细 — 原生客户端

### 6.1 采集

| 项 | 实现 |
| --- | --- |
| 机制 | `Clipboard.getData(kTextPlain)` **每 2 秒轮询**（Flutter 无跨平台变更事件） |
| 类型 | 仅纯文本 |
| 启动条件 | 已配置 Key **且** 用户显式开启监听（默认关闭） |
| 去重 | ① 内存 `_lastSeen` 字符串比较（**上传前即更新**）② 持久化 `DedupStore` 存**最后一次成功上传**文本的 SHA-256，无 TTL，换 Key 时清空 |
| 大小预校验 | 本地按字节比对服务端上限（`GET /meta` 学得，回退 100 KiB） |

**平台行为**：

| 平台 | 采集范围 |
| --- | --- |
| Windows / macOS / Linux | 应用常驻即持续轮询（关窗隐藏到托盘后仍采集） |
| Android / iOS | **仅前台**（`AppLifecycleState.resumed`），系统限制 |

### 6.2 上传管线

```
uploadText(text, source)
  → 空值校验 → SHA-256 去重 → 字节上限预校验
  → 重试：立即 / +1s / +2s（共 3 次，无指数退避、无抖动）
      · 401 → 立即中止，提示更新 Key（不重试）
      · 413 → 立即中止，提示超限（不重试）
  → 成功：更新 dedup 摘要 + 记录同步时间
  → 失败：入离线上传队列（最多 500 条，FIFO，本地 JSON 持久化）
      · 30s 定时补传 + 成功后机会性补传
      · 401 保留队列待换 Key；413 丢弃该条并提示；超限丢最旧并提示
```

### 6.3 同步与列表

- **每 3 秒全量拉取** `GET /history`，无分页、无增量、无条件请求、无差异比对。
- 自动刷新在非 `resumed` 时暂停。
- 筛选（平台 + 文本）**全部在客户端内存中完成**。
- 桌面卡片在 <1040px 且选中记录时侧栏整体隐藏（`SizedBox.shrink()`，无动画）。

### 6.4 连接配置

| 环节 | 实现 |
| --- | --- |
| 首次配置 | `KeyConfigScreen`：服务地址 + Key（可遮蔽），保存前强制连通性校验 |
| 导入方式 | 「从剪贴板导入」全平台可用；「扫码导入」**仅 Android/iOS** |
| 配置串 | `driftclip://connect?server=…&key=…`（解析后**仅预填表单**，仍需用户点保存） |
| 连通性校验 | `GET /history` + 8s 超时；区分 401（Key 无效）/ 超时 / 无法连接三种文案 |
| meta 协商 | 校验成功后读 `GET /meta`，缓存服务端版本与字节上限 |
| 持久化 | `shared_preferences`（`api_base_url`/`api_key`/`listen_enabled`/`auto_start`/`installation_id`/meta 缓存） |
| 重新配置 | 设置页「编辑连接」弹窗，同一校验路径 |

> ⚠️ `driftclip://` **不是系统深链**：任何平台清单中都未注册 URL Scheme，Web 端二维码无法唤起应用，只能靠扫码/剪贴板传入。
> ⚠️ API Key 以**明文存于 SharedPreferences**，未使用 Keychain / Keystore。

### 6.5 界面结构

| 形态 | 断点 | 布局 |
| --- | --- | --- |
| 桌面壳 | ≥ 720px | 左侧栏 232px + 历史列表 + 右侧详情栏 360px |
| 移动端 | < 720px | AppBar + 历史列表 + FAB「手动输入」；详情为可拖拽底部抽屉 |

**桌面快捷键**：`⌘/Ctrl+N` 手动输入 · `⌘/Ctrl+R` 刷新 · `⌘/Ctrl+,` 设置 · `⌘/Ctrl+F` 聚焦搜索 · `Esc` 关闭详情。

**侧边栏**：品牌区 + 监听状态芯片 + 刷新；「全部」+ 按平台分区（固定顺序 macOS/Win/Linux/Android/iOS/Web）带计数；底部「手动输入 / 设置 / 关于」。

**设置页分区**：
- 同步：剪贴板监听开关
- 启动（仅桌面）：登录后自动启动
- 连接：服务地址 / Key（掩码显示）/「编辑连接」
- 关于：版本号 + 仓库地址（点击复制）

### 6.6 平台集成

| 能力 | 实现 |
| --- | --- |
| 托盘 | 图标 + 菜单：打开主窗口 / 暂停·恢复监听 / 待同步状态 / 退出 |
| 关窗行为 | 监听开启 → 隐藏到托盘；未开启 → 退出（**由监听开关派生，无独立偏好**） |
| macOS 复活 | `applicationShouldTerminateAfterLastWindowClosed = false` + `applicationShouldHandleReopen` |
| 自启动 | Windows/Linux 用 `launch_at_startup`；**macOS 自研 MethodChannel + `SMAppService`（需 macOS 13+）** |
| 权限 | Android `INTERNET` + `CAMERA`；iOS `NSCameraUsageDescription` |
| 明文 HTTP | Android `network_security_config` + iOS ATS 例外放行（自托管内网 IP 必需） |
| 通知 | **无** |

### 6.7 设备元数据上报

| 字段 | 来源 |
| --- | --- |
| `platform` | `Platform.operatingSystem` |
| `os_version` | `Platform.operatingSystemVersion` |
| `device_model` | ⚠️ `Platform.localHostname`（**是主机名，非硬件型号**；移动端常为空） |
| `app_version` | `package_info_plus` |
| `installation_id` | `Random.secure()` 生成的 UUIDv4，本地持久化 |

---

## 7. 数据模型与 API 契约

### 7.1 SQLite Schema

```sql
accounts(id PK, email UNIQUE, password_hash, created_at)
sessions(id PK, account_id FK, token_hash UNIQUE, expires_at)
         INDEX(account_id)
keys(account_id PK FK, key_hash UNIQUE, key_encrypted BLOB, key_nonce BLOB, created_at)
history(id PK, account_id FK, content, source, received_at, public_ip,
        platform, os_version, device_model, app_version, installation_id)
        INDEX(account_id, received_at DESC, id DESC)   -- 列表排序 + 保留淘汰共用
```

**时间约定**：全部以 **RFC3339 UTC 字符串**存储。其字典序即时间序，`received_at` 是排序、筛选、淘汰的**唯一依据**；同秒多条以自增 `id` 决胜。

**PRAGMA**：`journal_mode=WAL` · `busy_timeout=5000` · `foreign_keys=ON`；连接池上限 8。

### 7.2 API 契约（14 个端点）

| 方法 | 路径 | 鉴权 | 限流 | 请求 | 响应 |
| --- | --- | :-: | :-: | --- | --- |
| GET | `/api/v1/meta` | 公开 | — | — | `{version, max_history_records, max_clipboard_text_bytes}` |
| POST | `/api/v1/auth/register` | 公开（CSRF 豁免） | IP 10/min | `{email, password}` | 201 `{email}` |
| POST | `/api/v1/auth/login` | 公开（CSRF 豁免） | IP 10/min | `{email, password}` | 200 `{email}` |
| POST | `/api/v1/auth/logout` | 会话 | — | — | 204 |
| POST | `/api/v1/auth/change-password` | 会话 | — | `{current_password, new_password}` | 204（作废全部会话） |
| GET | `/api/v1/auth/me` | 会话 | — | — | `{email}` |
| GET | `/api/v1/keys` | 会话 | — | — | `{has_key}` |
| GET | `/api/v1/keys/secret` | 会话 | — | — | `{key}`（无密文副本时 409） |
| POST | `/api/v1/keys` | 会话 | — | — | 201 `{key}`（已存在时 409） |
| POST | `/api/v1/keys/reset` | 会话 | — | — | 200 `{key}`（无 Key 时 409） |
| GET | `/api/v1/history` | 会话 **或** Key | — | `?page&page_size&platform&q&from&to` | `{items, total, page, page_size}` |
| GET | `/api/v1/history/{id}` | 会话 **或** Key | — | — | 详情（含 `content` 全文 + `public_ip`） |
| POST | `/api/v1/history` | **仅 Key** | 账户 120/min | `{content, source, platform, os_version?, device_model?, app_version?, installation_id?}` | 201 `{id, received_at}` |
| DELETE | `/api/v1/history/{id}` | 会话 **或** Key | — | — | 204 |
| POST | `/api/v1/history/batch-delete` | 会话 **或** Key | — | `{ids: number[]}` | `{deleted}` |
| POST | `/api/v1/history/clear` | 会话 **或** Key | — | — | `{deleted}` |

**列表参数**：`page` 默认 1（上限 1000 万，防 offset 溢出）· `page_size` 默认 20（**上限 100**）· `platform` 枚举校验 · `q` 子串（`LOWER(content) LIKE '%…%' ESCAPE '\'`，转义通配符）· `from`/`to` 闭区间 · 条件 AND。

**列表投影（性能关键）**：仅返回 `substr(content, 1, 500)` 预览，**不返回全文与 `public_ip`**；全文与 IP 只在详情接口返回。

**排序**：`received_at DESC, id DESC`（API **无排序参数**）。

**Key 格式**：`dc_` 前缀 + ≥32 字节随机值。

### 7.3 配置项

| 分组 | 键 | 默认值 |
| --- | --- | --- |
| server | `listen_addr` / `business_timezone` / `trusted_proxies` / `require_https` | `0.0.0.0:8080` / `Asia/Shanghai` / `[]` / `false` |
| registration | `enabled` | `true` |
| history | `max_history_records` | **1000** |
| history | `max_clipboard_text_bytes` | `102400`（100 KiB） |
| security | `session_duration_days` | `30` |
| security | `session_secret` / `key_pepper` | **必填强随机**，占位值会告警 |
| rate_limit | `enabled` / `auth_limit` / `auth_window_seconds` | `true` / `10` / `60` |
| rate_limit | `upload_limit` / `upload_window_seconds` | `120` / `60` |
| database | `path` | `driftclip.sqlite` |
| web | `static_dir` | `web/dist` |

全部可用 `DRIFTCLIP_*` 环境变量覆盖（优先级：默认 < YAML < 环境变量）。

---

## 8. 产品规则与不变量（重建必须保留）

以下是产品承诺与安全基线，**重做时不能丢**：

### 8.1 数据与时间

1. 仅接受 **UTF-8 纯文本**；空内容不上传；单条超限**明确报错不截断**。
2. `received_at` 由**服务端**写入，是排序/筛选/淘汰的唯一依据，**不信任客户端时间**。
3. 业务展示时区 `Asia/Shanghai`（UTC+8）。
4. 保留上限**按账户**计算（不按设备）；写入与淘汰原子完成。
5. 正文/公网 IP/设备元数据随记录一并删除，无软删除。

### 8.2 安全基线

6. **账户严格隔离**：越权一律 404，不泄漏存在性。
7. 密码 Argon2id；会话仅存哈希；Key 仅存 pepper 哈希（+ 可选密文副本）。
8. 日志**不含** Key / 密码 / 会话 / 正文。
9. 所有 SQL 参数化；模糊查询转义 LIKE 通配符。
10. 登录失败文案统一，防账户枚举。
11. 注册/登录 CSRF 豁免（本就无会话保护），其余状态修改接口需 `X-Requested-With`。
12. 公网 IP **只由服务端观测**，不接受客户端提交。
13. 设备元数据**仅用于展示与筛选**，不作为安全依据；不采集序列号/MAC/广告 ID/位置。

### 8.3 平台诚实性

14. 移动端**仅前台采集**是系统限制，不是缺陷；对外表述按"取回为主"预期管理。
15. 破坏性操作（清空全部 / 重置 Key）需 **5 秒倒计时**二次确认。
16. 失败**必须对用户可见**——静默丢失比没有功能更伤信任。
17. 自托管场景需放行明文 HTTP，但文档须明示风险并建议 HTTPS。

### 8.4 明确不做（第一版范围外）

服务端去重 · 邮箱验证 · 密码找回 · 多 Key/设备独立 Key · 富文本与图片 · 应用层静态加密 · 自动备份 · Web 端写入 · WebSocket/推送 · 全文索引。

---

## 9. 已确认的实现缺陷

> 以下为读码确认的**实际存在**的问题，非推测。重建时应视为待修复清单。

### 9.1 严重（影响数据可靠性）

| # | 位置 | 问题 |
| --- | --- | --- |
| **S1** | `client/lib/main.dart:73` | **离线上传队列从未接线**。`UploadQueue` 已创建并传入 `DriftClipApp`，但构造 `HomeShell` 时**未转发 `queue`** → 协调器的 `queue` 恒为 `null` → 失败入队直接 no-op。**净效果：3 次重试失败后内容静默丢失**，且托盘待同步数、同步状态行、队列已满提示四套 UI 全部是死代码。 |
| **S2** | `client/lib/services/clipboard_monitor.dart:72` | 内存 `_lastSeen` 在**上传结果返回前**就更新 → 上传失败的文本本会话内不再被轮询器重试，与 S1 叠加成彻底丢失。 |
| **S3** | 客户端全量 | 网络失败**无任何横幅/吐司/持久指示**，`uploadText` 返回 `false` 被轮询器忽略。 |
| **S4** | `client/lib/services/settings_screen.dart:88` | `key.substring(0, 5)` 对长度 < 5 的 Key 抛 `RangeError`；`apiKey` setter 只 trim 不校验长度。 |
| **S5** | `web/src/pages/KeysPage.tsx:101` vs `:132` | `GET /keys` 失败时 `hasKey` 停留 `null`，骨架分支**先 return**，错误 Alert 永远不可达 → 页面**永久卡在骨架屏**。 |
| **S6** | `web/src/pages/HistoryPage.tsx:189-193` | 详情拉取失败的 `catch` 是空操作，但 `setExpandedId` 仍执行 → 开关翻转、内容区空白、**零错误反馈**。 |
| **S7** | `web/src/pages/HistoryPage.tsx:86-87` | 每次 `load()` 无条件 `setExpandedId(null)` + `setSelected(new Set())` → 5 秒自动刷新下多选与详情展开**不可用**。 |
| **S8** | `web/src/pages/HistoryPage.tsx:100-105` | 清空全部的 5 秒倒计时**结束后不会自动取消**，「确认清空全部」按钮**永久保持待触发状态**。 |
| **S9** | `web/src/lib/api.ts:30-32` | **无全局 401 处理**。会话过期只在当前页弹原始错误，**不会跳登录页**。 |
| **S10** | `client/lib/screens/settings_screen.dart:35` | 自启动开关状态**从不与操作系统对账**；原生已实现的 `isLoginItemEnabled` 从未被 Dart 调用；注册失败被吞掉而开关仍显示为开。 |
| **S11** | `client/lib/screens/desktop_shell.dart:177` + `nav_sidebar.dart:99` | 侧栏监听状态芯片**不可点击**（与自身文档注释矛盾），且从**托盘**切换监听后芯片**不会刷新**（`SettingsStore` 无变更通知）。 |

### 9.2 性能

| # | 位置 | 问题 |
| --- | --- | --- |
| **P1** | 服务端 `GET /history` | **无 `since`/cursor 增量参数**，客户端每 3s 拉全量，Web 每次刷新拉当前页。保留上限提到 1000 后成本线性上升。 |
| **P2** | `web/src/pages/HistoryPage.tsx:386-507` | **无虚拟化**，20 条全部渲染为真实 Card DOM。 |
| **P3** | `HistoryPage.tsx:161,174,210` | 任何变更（删 1 条）都**整页重取**，无乐观更新。 |
| **P4** | `ConnectGuide.tsx:26` + `App.tsx:7-11` | 二维码在**主线程**生成 base64 PNG；`qrcode` 静态导入进首屏包，**无代码分割**。 |
| **P5** | `HistoryPage.tsx:103` / `KeysPage.tsx:40` | 倒计时每秒 `setState`，**整个列表重渲染 20 行**（行未 memo）。 |
| **P6** | `client/lib/widgets/history_content.dart:795` | 桌面卡片 `IntrinsicHeight` → **每项二次布局**，Flutter 公认性能反模式。 |
| **P7** | `history_content.dart:280-294` | 每 3s 无条件重赋值 `_records`，**即使响应逐字节相同**也全量重建。 |
| **P8** | `history_content.dart:357-368` | `_filtered` 每次 `build` 重新分配；搜索**无防抖**，每敲一键全量重建。 |
| **P9** | `client/lib/services/api_client.dart:62-104` | 列表/上传/删除**全部无超时**（仅 `validate` 有 8s）→ 服务端挂起时永久 loading，无取消路径。 |
| **P10** | `upload_coordinator.dart:94,112` | 每次上传在 UI isolate 做 `utf8.encode` 全量拷贝（哈希 + 长度检查各一次）。 |

### 9.3 外观与交互

| # | 问题 |
| --- | --- |
| **V1** | 布局固定 `max-w-960px`，桌面宽屏大量留白，无宽屏模式。 |
| **V2** | 历史行是**大卡片纵向堆叠**，纵向密度极低（一条一屏），1000 条时浏览体验差。 |
| **V3** | **平台色已定义但完全未使用**——平台徽标是无色 outline 文本，五个平台视觉上无区分。 |
| **V4** | 详情面板 `source` 显示原始英文 `clipboard`/`manual`，与列表中文徽标「剪贴板/手动」**不一致**。 |
| **V5** | 平台筛选下拉**直接显示原始 key**（`macos`），未中文化。 |
| **V6** | 深色模式**无手动开关**；二维码容器**硬编码 `bg-white`**，深色下是白块。 |
| **V7** | **无对话框组件**（装了 `@radix-ui/react-dialog` 未用），两个破坏性流程都是按钮内联状态。 |
| **V8** | 正文一律 `Text` 渲染，**无等宽字体、无语法/命令高亮、无链接识别**，命令与 URL 难以快速扫读。 |
| **V9** | 倒计时/刷新等状态**每秒重渲染**；行悬停才有 100% 不透明度，**无 `@media (hover:hover)` 守卫**（触屏下点击不到删除）。 |
| **V10** | 详情 `<pre>` **无 `max-height`**，一条超长记录可占满整页。 |
| **V11** | **空态不区分**「无记录」与「筛选无结果」，且未提供清除筛选入口。 |
| **V12** | 时间范围输入**无可见标签**；无时间区间快捷选项（今天/本周）。 |
| **V13** | 排版刻度止于 22px，系统字体栈无 webfont，**整体观感扁平**。 |
| **V14** | 客户端 720px 断点只看宽度：700px 桌面窗拿到移动端布局（FAB + 底部抽屉）；选中记录且 <1040px 时侧栏**瞬间消失且无动画**。 |
| **V15** | 客户端 `compact` 开关让卡片与工具栏**分叉成两套视觉**（字号 11 vs 12、详情底部抽屉 vs 右侧栏），平台间视觉漂移。 |

### 9.4 可访问性

- Web 登录/注册页**无 `<h1>`**（CardTitle 渲染 `<h3>`），标题层级从 h3 开始。
- 客户端 `lib/` 中**完全没有 `Semantics`**；桌面紧凑卡片**无法用键盘聚焦或激活**，列表实为纯鼠标操作。
- 无 `prefers-reduced-motion` 支持。
- 无 `aria-live` 区域；复选框无关联标签；删除后无撤销。

---

## 10. 重建建议：性能

按投入产出比排序：

### 10.1 服务端（收益最大）

| 优先级 | 改动 | 预期收益 |
| --- | --- | --- |
| **P0** | 列表接口加 **`since_id` 游标**（或 `updated_since`），返回 `{items, next_cursor, has_more}` | 3s 轮询从 O(全量) 降为 O(增量)，通常是 **10~100 倍**缩减 |
| **P0** | 响应加 **ETag / `If-None-Match`** → 304 空体 | 无变更时传输降为几百字节 |
| **P1** | 正文搜索启用 **SQLite FTS5**（`content` 虚表 + 触发器同步） | 1000+ 条下 `LIKE '%…%'` 全表扫描 → 索引查找 |
| **P1** | 列表默认 `page_size` 提到 50~100；Web 端引入**虚拟滚动**（`@tanstack/react-virtual`） | 一次翻页覆盖更多，DOM 节点恒定 |
| **P2** | 保留淘汰从「每次上传都跑一次全账户 DELETE」改为**低频/增量触发**（如超限 10% 才清） | 减少高频写事务与 WAL 压力 |
| **P2** | `CountHistory` 与 `ListHistory` 合并为窗口函数 `COUNT(*) OVER()`，省一次查询 | 列表请求 DB 往返减半 |
| **P2** | 加 `devices` 表（见 §12.3），替代裸 `installation_id` 字符串 | 支撑设备管理与单设备吊销 |

### 10.2 Web 端

- **路由级代码分割**：`React.lazy` + `Suspense`；`qrcode` 改为动态 `import()`，只在 Key 页加载。
- **服务端状态化**：用 TanStack Query（或 SWR）替代手写 `useEffect`——自动获得缓存、请求去重、后台标签页暂停（`refetchOnWindowFocus`）、乐观更新、失效重取。
- **增量合并**：收到增量记录时**局部插入**而非整页替换，保留滚动位置与选中/展开状态。
- **行组件 `memo` 化**：倒计时/刷新状态与行内容解耦，秒级 tick 不再重渲染 20 行。
- **筛选同步到 URL query**（`useSearchParams`）：可分享、可收藏、刷新不丢、浏览器前进后退可用。
- **搜索防抖** 250~300ms + `AbortController` 取消过期请求。
- **复制走剪贴板 API 时提供降级**（`document.execCommand` 或提示手动），非安全上下文不静默失败。
- 二维码移出主线程（`OffscreenCanvas` / Worker），或改用 SVG 输出避免 base64 膨胀。

### 10.3 客户端（Flutter）

- **改 3 秒全量轮询为增量拉取**（`since_id` 游标 + 本地合并），同时把 `Clipboard.getData` 降到 1s 或改用原生变更监听。
  - 桌面可用 `NSPasteboard` changeCount、Android `ClipboardManager` listener 做**事件驱动**，彻底去掉轮询。
- **把 SHA-256 与字节计数移出 UI isolate**（`compute()` / isolate），`utf8.encode` 长度改用计数编码器避免全量拷贝。
- **去掉 `IntrinsicHeight`**，改用 `Row` + `Expanded` 或固定高度约束。
- **引入真正的状态管理**（Riverpod/BLoC）+ `SettingsStore` 变更通知，消除 `setState(() {})` 空刷新与 `ValueKey` 强制重建整棵子树的黑魔法。
- **搜索防抖 + 列表虚拟化**（`ListView.builder` 已有；补 `itemExtent` / `prototypeItem` 减少测量）。
- **所有网络调用加超时与取消**（`http` 包 `.timeout()` + `CancellationToken`）。
- **队列改 SQLite/追加日志**，避免每次入队全量重写 JSON；顺便修好 S1 的接线。
- 详情正文**预取 + 缓存**（滚动进入视口时预取），消除每次复制都打一次详情请求。

---

## 11. 重建建议：外观

### 11.1 信息架构

- 引入**左侧导航**（桌面 ≥1024px）替代顶部栏，与客户端壳层统一心智；中间列表 + 右侧详情的**三栏布局**，取代当前「一行一卡片」的纵向流（直接解决 V1、V2）。
- 筛选条件收进**可折叠筛选栏 / 命令面板**（`⌘K` 全局搜索直达），默认只留一个搜索框 + 平台芯片组。
- 移动端保持单列，但**列表项改为紧凑行**（2 行以内：正文首行 + 元信息行），底部导航代替 AppBar 三点。

### 11.2 视觉语言

| 项 | 建议 |
| --- | --- |
| **平台色** | 启用已定义的 `--platform-*` 七色，为五个平台做**图标 + 色彩**双重标识（解决 V3），并在筛选芯片、侧栏计数、列表行统一使用。 |
| **正文排版** | 按内容类型自适应：命令/代码片段用**等宽字体 + 轻量语法着色**；URL 自动识别为可点击链接并显示域名；纯文本用正文刻度。这是最能提升「一眼可扫读」的改动（解决 V8）。 |
| **密度** | 提供 紧凑/舒适 两档密度；桌面默认紧凑（行高 44~52px），移动端舒适。 |
| **深色模式** | 从「跟随系统」升级为 **跟随系统 + 手动覆盖**，存入用户偏好；修掉二维码硬编码白底（解决 V6）。 |
| **排版刻度** | 引入 webfont 变量字体（如 Inter + 思源黑体），扩展至 12/13/14/16/20/24/32 七档；正文最大宽度限制 68ch 提升长文本可读性。 |
| **层级** | 用真实投影与 1px 描边区分三级表面（画布 / 卡片 / 浮层），替代当前几乎全平的边框语言。 |
| **状态反馈** | 统一 Toast / Banner / Skeleton 三件套；行内操作用 hover 显现但加 `@media (hover:hover)` 守卫（解决 V9）；骨架屏覆盖翻页与筛选（当前只有首屏）。 |
| **破坏性操作** | 换成真正的**确认对话框**（已装 `@radix-ui/react-dialog` 却未用），明确列出影响条数，倒计时内提供取消（解决 V8、S8）。 |
| **空态** | 区分「还没有记录」与「没有匹配结果」，后者给出**一键清除筛选**（解决 V11）。 |
| **时间** | 列表用相对时间 + 悬浮绝对时间；筛选区提供「今天 / 本周 / 本月」快捷项替代裸 `datetime-local`（解决 V12）。 |
| **文案一致性** | 平台名、来源名统一走 i18n 字典，`macos` → 「macOS」、`clipboard` → 「剪贴板」（解决 V4、V5）。 |

### 11.3 交互增强（按性价比）

1. **键盘优先**：`⌘K` 搜索、`↑↓` 移动、`Enter` 复制、`Esc` 关闭、`⌘Z` 撤销删除。
2. **删除可撤销**：Toast 内 5 秒撤销（比二次确认体验更好，且不阻碍批量操作）。
3. **筛选即时应用**：文本/平台改动自动生效（防抖），去掉「应用」按钮；时间范围仍需显式确认。
4. **URL 即状态**：筛选、页码、详情项全部反映在地址栏。
5. **增量插入动画**：新记录从顶部滑入，让「刚复制的内容」有即时反馈。
6. **长列表锚点**：刷新/筛选后保持滚动位置与展开项（解决 S7）。
7. **移动端下拉刷新 + 上拉加载**替代翻页按钮。

---

## 12. 重建建议：架构与范围

### 12.1 技术选型

| 层 | 现状 | 建议 |
| --- | --- | --- |
| 服务端 | Go + SQLite | **保持**。单二进制 + SQLite 是这个产品的核心优势，不要为了"现代化"换 Postgres/Redis。增量同步（FTS5 + `since` 游标）足以支撑万级记录。 |
| Web | React 19 + Vite + Tailwind 3 | **保持 React**。补齐：TanStack Query、虚拟列表、Tailwind 4（CSS-first 令牌）、路由懒加载。若追求极致首屏可评估预渲染。 |
| 客户端 | Flutter | **保持 Flutter**（唯一能低成本覆盖 5 平台的方案）。补齐：Riverpod 状态管理、SQLite 队列、isolate 卸载、原生剪贴板事件监听。 |
| 令牌 | JSON → 生成 CSS + Dart | **保留并强化**：新增排版/间距/动效/层级令牌，把 i18n 字典也纳入同一生成管线。 |

### 12.2 建议的重建顺序

```
阶段 1  修数据可靠性缺陷（S1–S11）—— 离线队列接线、401 全局处理、
        清空倒计时可取消、刷新不清状态。这是产品底线，未达成前不加功能。
阶段 2  增量同步（服务端 since 游标 + ETag）→ 客户端/Web 改增量拉取。
        一次性解决 P1、P3、P7，并让 1000 条上限真正可用。
阶段 3  外观重做（三栏布局 + 平台色 + 等宽正文 + 深色模式开关 +
        确认对话框 + 空态区分 + 虚拟滚动）。
阶段 4  体验增强（键盘优先、撤销删除、⌘K、筛选入 URL、i18n 英文补齐）。
阶段 5  结构升级（多设备独立 Key / 设备管理 / 可选图片 / 富文本）。
```

> **原则**：核心闭环可靠先于功能增加；性能与外观的改进应在可靠性缺陷修完之后做，否则是在不稳定的地基上盖楼。

### 12.3 值得在重建中兑现的遗留需求

原 `ROADMAP.md` P4 中仍然合理、且能显著提升产品完整性的：

| 功能 | 说明 |
| --- | --- |
| **每设备独立 Key + 设备管理** | `devices` 表以 `installation_id` 为主键：设备命名、最后活跃、单设备吊销、密钥轮换。解决「一把 Key 泄露即全账户沦陷」的根本问题（`keys` 表以 `account_id` 为主键是当前最大安全短板）。 |
| **按时间保留** | 在条数上限之外提供「保留 N 天」，更贴合真实使用。 |
| **i18n** | 目标用户是英文自托管社区，先补英文；令牌与文案一起进生成管线。 |
| **Web 端手动写入** | 解除「仅 Key 上传」限制，允许 Web 会话 `POST /history`（当前是刻意的不变量，重做时需明确取舍）。 |
| **导出** | 一键导出 JSON/纯文本/CSV。 |
| **内容类型识别** | 在数据模型里预留 `content_type`（text/url/code），为富文本与图片留出扩展位。 |

---

## 附录 A：功能验收基线（重建后应全部通过）

来自原 `CLIPBOARD_SYNC_V1_PLAN.md` §10，10 条：

1. 两台配置同一 Key 的设备上传后，原生端与 Web 可见同一账户历史。
2. 不同账户的 Key 与会话**绝不**能读取或删除彼此记录。
3. 每条记录展示正文、来源、UTC+8 服务端时间、完整 IP 与设备元数据。
4. 每账户最多保留配置数量的最新记录，超出按接收时间删最旧。
5. 连续复制已成功上传的相同文本不再发请求；失败时不更新去重状态。
6. Key 重置后旧 Key 立即失效，新 Key 可访问原有历史。
7. Web 与原生端均支持单删、多选删、5 秒确认后清空。
8. Web 与原生端均支持平台 + 文本子串 + 时间范围组合筛选。
9. iOS/Android 前台可采集；桌面监听开启时托盘常驻采集。
10. 明文 HTTP、无效 Key、空正文、超限正文均被服务端拒绝。

**追加基线（针对已确认缺陷）**：

11. 断网复制 3 条 → 恢复网络 → 3 条全部按序补传，无丢失。
12. 粘贴超长文本有明确提示，不静默丢弃。
13. 会话过期时任意端自动跳登录页，不停留在错误态。
14. 自动刷新不打断用户的多选、展开与滚动位置。
15. 破坏性操作确认对话框可随时取消，倒计时结束不残留可触发状态。

## 附录 B：环境与运行

| 工具链 | 版本 |
| --- | --- |
| Go | 1.26+（国内需 `GOPROXY=https://goproxy.cn,direct`） |
| Node.js | 24+ |
| Flutter | 3.44+ |
| SQLite | WAL 模式，`modernc.org/sqlite` 驱动（纯 Go，无 CGO） |

```bash
# 服务端
cd server && go run ./cmd/driftclip-server      # :8080
# Web
cd web && npm install && npm run dev          # :5173，/api 代理到 8080
# 客户端
cd client && flutter run -d macos
```
