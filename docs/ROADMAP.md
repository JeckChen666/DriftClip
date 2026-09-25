# DriftClip 改进路线图（v0.1 → v0.3）

> **进度（2026-09-26）：** P0–P3 已全部实现并通过自动化验证（服务端 `go test ./...`、客户端 `flutter test` 46 例、Web 13 例、macOS 构建冒烟）。
> 托盘/自启动/扫码/Android 联网等依赖真机的验收项见 `DEVELOPMENT.md`「真机验收清单」。P4 未启动。

**来源：** 2026-09 产品评审（基于服务端 / Web / Flutter 客户端全量盘点）
**原则：** 先兑现已承诺的，再承诺新的。每个阶段可独立发布、独立验收；沿用证据驱动的验收方式；不引入遥测，不降低现有安全基线。

## 指导原则

1. **诚实化优先。** "表面存在但实际无效"的功能（托盘、macOS 自启动）比没有更伤信任：修复之前先隐藏或如实标注。
2. **核心闭环可靠先于功能增加。** 关窗后仍在捕获、断网不丢数据、失败用户可见——这是剪贴板工具的底线，未达成前不扩功能。
3. **激活漏斗对齐产品承诺。** "never lose a link" 的前提是新用户能在 10 分钟内体验到跨设备取回，且默认配置不与之矛盾。
4. **Spec 是权威。** 涉及范围或不变量的改动，先修订 `docs/easypower/clipboard-sync/spec.md` 与 CHANGELOG，再实现（见文末"Spec 修订清单"）。

## 已确认的关键事实（2026-09-26 核查）

| # | 事实 | 位置 | 影响 |
| --- | --- | --- | --- |
| 1 | Android main 清单无 `INTERNET` 权限（仅 debug/profile 有）→ **release APK 完全无法联网** | `client/android/app/src/main/AndroidManifest.xml` | 发布产物不可用，P0 |
| 2 | Android 9+/iOS 默认拒绝明文 HTTP，未配置豁免 → 内网 `http://IP:8080` 场景开箱不可用 | 同上；iOS Info.plist 无 ATS 例外 | P2 |
| 3 | 托盘零实现：`tray_manager` 仅在 pubspec，Dart 代码无调用 | `client/pubspec.yaml:40` | P1 |
| 4 | macOS 关闭最后一个窗口即退出进程，捕获随之中止 | `client/macos/Runner/AppDelegate.swift:6-8` | P1 |
| 5 | macOS 登录自启动开关疑似无效（插件注册待真机验证） | `client/lib/services/desktop_integration.dart:36-47` | P1 |
| 6 | 上传重试 3 次（1s→2s）后放弃该条，无离线队列 | `client/lib/services/upload_coordinator.dart` | P1 |
| 7 | 413（单条超 100 KiB）无专门处理：静默重试后丢弃，无提示 | `client/lib/services/upload_coordinator.dart` | P0 |
| 8 | 版本号不一致：硬编码 `0.1.0` vs pubspec `1.0.0+1` | `client/lib/services/device_info.dart:17` | P0 |
| 9 | Keys 页无连接引导：无下载链接、无二维码、无分步说明 | `web/src/pages/KeysPage.tsx:126-128` | P2 |
| 10 | 每账户仅一把 Key，重置即全设备下线；无设备列表/单设备吊销 | `server/internal/store/store.go:68-75` | P4 |
| 11 | 服务端无 since/cursor 增量参数，客户端每 3s 拉全量 | `client/lib/services/api_client.dart:113-122` | P4 |
| 12 | 无限流、密码无强度要求、忘记密码即账户不可恢复 | `server/internal/handler/auth.go` | P3 |

---

## P0 — 止血与诚实化（hotfix，约 1 天）→ v0.1.1

> 目标：让已发布的产物可用，让产品表面与实际一致。全部改动低风险、不改变业务不变量。

| # | 改动 | 模块 | 验收 |
| --- | --- | --- | --- |
| 0.1 | main 清单补 `INTERNET` 权限 | client/android | release APK 可连接服务端（真机走查） |
| 0.2 | 应用名 `driftclip_client` → `DriftClip`；替换启动图标 | client/android | 桌面图标与名称正确 |
| 0.3 | Android release 签名：CI 注入正式 keystore（或文档化自签名流程），移除 debug 签名 | client/android、CI | release 产物带正式签名 |
| 0.4 | 修复前先隐藏 macOS 自启动开关；README/CHANGELOG 中托盘、常驻表述与实际对齐 | client、docs | 设置页无失效开关；文档无未兑现承诺 |
| 0.5 | 版本号统一：读 package_info（或单一常量源），与 pubspec 对齐 | client | 任意端上报的 app_version 与构建号一致 |
| 0.6 | 413 处理：识别后不重试、立即提示"超过单条上限"；本地按字节预校验 | client | 粘贴超长文本有明确反馈，不静默丢失 |

## P1 — 桌面常驻与数据可靠性（约 1~2 周）→ v0.2.0

> 目标：核心底线成立——关窗仍在捕获、断网不丢数据、失败可见。这是产品成立的前提。

| # | 改动 | 模块 | 验收 |
| --- | --- | --- | --- |
| 1.1 | 托盘常驻：图标 + 菜单（打开主窗口 / 暂停恢复监听 / 退出）；需先补图标资源（见 `desktop_integration.dart` 注释） | client（Win/mac/Linux） | 三平台托盘可用；复制在窗口关闭后仍入库 |
| 1.2 | 关窗默认最小化到托盘（设置可改"直接退出"）；macOS `applicationShouldTerminateAfterLastWindowClosed` 返回 false，重复启动激活已有实例 | client | macOS 关窗后进程常驻；二次启动唤起主窗 |
| 1.3 | macOS 登录自启动修复：SMAppService（macOS 13+），插件注册问题排查，必要时原生 MethodChannel 兜底；**真机验证为准** | client/macos | 重启后免手动启动即开始捕获 |
| 1.4 | 离线上传队列：失败入队、指数退避补传、队列上限（如 500 条，超限丢最旧并提示）；换 Key 后队列重试 | client | e2e：断网复制 3 条 → 恢复 → 全部按序补传 |
| 1.5 | 同步状态可见：托盘菜单/界面显示"最后同步时间 + 待同步数"；扩展现有 401 横幅为通用异常状态条 | client | 弱网下用户能感知未同步状态 |

## P2 — 移动端可用与激活漏斗（约 1 周）→ v0.2.x

> 目标：新用户 10 分钟内完成"注册 → 装客户端 → 跨设备看到首条剪贴板"；移动端连内网 HTTP 可用。

| # | 改动 | 模块 | 验收 |
| --- | --- | --- | --- |
| 2.1 | 明文 HTTP：Android `network_security_config` 允许明文（自托管域名不可预知）；iOS ATS 例外；README 明示风险与 HTTPS 建议 | client/android、ios | Android/iOS 真机连 `http://内网IP:8080` 成功 |
| 2.2 | 错误文案指向根因：明文被系统拦截、无法解析主机、超时分别提示 | client | 模拟三类失败，文案可指导用户行动 |
| 2.3 | Keys 页连接引导：生成 Key 后展示分步引导（客户端下载链接 / 服务地址 / Key 复制 / 二维码编码 `driftclip://connect?server=…&key=…`） | web | 新用户按引导无需看文档完成连接 |
| 2.4 | 客户端导入配置：移动端扫码导入；桌面端"粘贴配置"一键导入；Android 注册深链 intent-filter | client | 扫码 3 秒完成配置并连通 |
| 2.5 | 激活走查计时记入 evidence（无遥测约束下的验收方式） | docs | 全新环境走查 ≤ 10 分钟 |

## P3 — 安全基线与承诺对齐（约 1 周）→ v0.3.0

> 目标：公网部署的安全底线补齐；产品承诺与默认配置一致。两项需先修订 Spec。

| # | 改动 | 模块 | 验收 |
| --- | --- | --- | --- |
| 3.1 | 限流：登录/注册按 IP+账户滑动窗口（内存实现，单二进制部署可接受），上传按账户限速；429 语义与客户端处理；可配置开关 ⚠️ Spec 修订 | server、client | 自动化测试覆盖限流触发与恢复 |
| 3.2 | 保留上限默认 100 → 1000（评估按天数保留作为可选项）；Web/客户端诚实展示"最多保留 N 条" ⚠️ Spec 修订 | server、web、client | 1000 条下列表/筛选/上传性能可用 |
| 3.3 | 版本协商：连接校验响应返回 server 版本与最低客户端版本；客户端过低提示升级；服务端记录设备 last_seen（为 P4 铺路） | server、client | 老客户端连新服务端有明确升级提示 |
| 3.4 | 注册成功页与 README 明示"密码丢失即账户不可恢复"；评估密码最小长度（≥8）⚠️ 若实行为不变量修订 | web、server | 提示可见；策略生效 |

## P4 — 结构性升级（按需启动，每项独立立项）

| # | 改动 | 说明 | 前置 |
| --- | --- | --- | --- |
| 4.1 | 设备管理 | devices 表（以 installation_id 为主键，客户端已上报元数据）：设备命名、最后活跃、单设备吊销；迁移期旧 Key 映射为账户级 Key；为每设备单独 Key 铺路 | 3.3 的 last_seen |
| 4.2 | 增量同步 | `GET /history?since_id=` 游标 + 客户端增量拉取；保留上限提升后为必做；为 SSE/推送预留 | 3.2 |
| 4.3 | i18n | Web + 客户端文案抽取，先补英文（目标用户是英文自托管社区） | 无 |
| 4.4 | Web 端写入 | `POST /history` 开放会话鉴权 + Web 手动添加入口 ⚠️ 当前 Spec 限定"仅 Key 上传" | Spec 修订 |
| 4.5 | FTS5 全文搜索 | 记录量上去后评估 | 3.2 / 4.2 |

---

## 依赖与发布节奏

```
P0 (hotfix) ──→ P1 (桌面常驻) ──→ v0.2.0
      └──────→ P2 (移动端/激活) ──→ v0.2.x     # P2 扫码依赖 P0 的 Android 联网修复
P3 (安全/承诺) ──→ v0.3.0                     # 与 P1/P2 无依赖，可并行
P4 各项独立立项，按需启动
```

- P0 与 P1、P2 的关系：P0 是 P2 的前置（Android 装了也连不上），立即发。
- P1 与 P2 可并行推进（分别由 client 和 web/server 承担）。
- 每阶段发布时同步 CHANGELOG 与 README；阶段验收沿用 `docs/easypower/*/evidence/` 的 e2e 截图/脚本模式。

## 移动端期望管理（写进 README，不进代码）

Android 10+ 系统限制后台读剪贴板，移动端"仅前台捕获"是平台约束而非缺陷；移动端的核心场景是**取回**（看历史、复制到本机），对外宣传与文档应按此表述，不做无法兑现的后台采集承诺。

## Spec 修订清单（实现前先改 Spec）

| 阶段 | 修订点 |
| --- | --- |
| P1 | 客户端范围加入：托盘常驻、关窗行为、离线上传队列（P05 计划已含托盘，属兑现而非扩权） |
| P3 | 移除"明确不做：上传/注册限流"；数据规模约束默认值 100 → 1000；视 3.4 结果修订密码规则 |
| P4.4 | 移除"仅 Key 上传"限定（如决定做 Web 写入） |

## 代理指标（无遥测约束）

- 全新环境激活走查时间（每阶段 evidence 记录，目标 ≤ 10 分钟）。
- GitHub issues 按失败类型分布（联网失败、数据丢失、连接配置为前三观察项）。
- Release 下载量与客户端版本分布（release 附件下载计数）。
