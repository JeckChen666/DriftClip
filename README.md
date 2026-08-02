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

## 开发环境

- Go 1.26+
- Flutter 3.44+
- Node.js 24+
