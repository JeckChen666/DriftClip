# DriftClip

**Self-hosted clipboard history. Copy on one device, find it on all of them.**

[![CI](https://github.com/JeckChen666/DriftClip/actions/workflows/ci.yml/badge.svg)](https://github.com/JeckChen666/DriftClip/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/JeckChen666/DriftClip)](https://github.com/JeckChen666/DriftClip/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

English | [简体中文](README.zh-CN.md)

DriftClip captures the text you copy on any device and keeps a synced, searchable history in one place. Run the server on your own machine or VPS, sign in from the web or the native apps, and never lose a link, command, or address again.

- Everything stays on infrastructure you control — a single Go binary with SQLite, no external services
- Multi-user with strict per-account isolation; web login via email + password, native apps via per-account API key
- Filter and search history by platform, text, and time; copy, delete, batch-delete, or clear all
- Text-only by design (max 100 KiB per record by default), with a per-account retention cap

| Web history | Mobile |
| --- | --- |
| ![Web history](docs/screenshots/web-history.png) | ![Mobile](docs/screenshots/web-mobile.png) |

Key management (keys can be re-revealed and copied at any time):

![Key management](docs/screenshots/web-keys.png)

## Architecture

| Module | Tech | Role |
| --- | --- | --- |
| `server/` | Go + SQLite | REST API, auth, retention, hosts the built web UI |
| `web/` | React + Vite | Browser client for browsing and managing history |
| `client/` | Flutter | Native apps for Windows / macOS / Linux / Android / iOS |

## Quick start (Docker)

```bash
git clone https://github.com/JeckChen666/DriftClip.git
cd DriftClip/deploy
export DRIFTCLIP_SESSION_SECRET="$(openssl rand -hex 32)"
export DRIFTCLIP_KEY_PEPPER="$(openssl rand -hex 32)"
docker compose up -d --build
```

The service listens on `127.0.0.1:8080` and keeps data in the `driftclip-data` volume. It is not meant to be exposed directly: put it behind your own reverse proxy with HTTPS, and set `DRIFTCLIP_SERVER_TRUSTED_PROXIES` (see [deploy/docker-compose.yml](deploy/docker-compose.yml)) — with `require_https` enabled the server rejects requests that did not arrive via a trusted HTTPS proxy.

A prebuilt image is also published to GHCR on every release:

```bash
docker run -d --name driftclip -p 127.0.0.1:8080:8080 -v driftclip-data:/data \
  -e DRIFTCLIP_DATABASE_PATH=/data/driftclip.sqlite \
  -e DRIFTCLIP_SESSION_SECRET="$(openssl rand -hex 32)" \
  -e DRIFTCLIP_KEY_PEPPER="$(openssl rand -hex 32)" \
  ghcr.io/jeckchen666/driftclip:latest
```

### First run

1. Open the web UI (e.g. `http://127.0.0.1:8080` locally) and register an account.
2. Go to **Keys** and generate your API key — you can view and copy it again at any time on the **Keys** page (stored encrypted server-side).
3. Install a native client, enter your server address and the key in the onboarding/settings screen.
4. Copy something on any connected device — it appears in the history everywhere.

Registration can be disabled for existing deployments (`DRIFTCLIP_REGISTRATION_ENABLED=false`).

## Native clients

Prebuilt clients for Windows, macOS, Linux, and Android are attached to every [release](https://github.com/JeckChen666/DriftClip/releases). Server release bundles include the binary, the web UI, and an example config.

- **macOS**: downloads are unsigned. If Gatekeeper blocks the app, remove the quarantine attribute: `xattr -cr /Applications/DriftClip.app`
- **Linux**: the bundle needs the usual Flutter runtime libraries (`libgtk-3-0`, `libblkid1`, `liblzma5`, …)
- **Android**: sideload the APK
- **iOS**: build from source with Xcode and your own signing (App Store distribution is up to you)

Mobile notes:

- Plain-HTTP servers (`http://LAN-IP:8080`) are common for self-hosting, so the mobile apps allow cleartext traffic. Prefer HTTPS (behind your reverse proxy) whenever possible — clipboard content is sensitive.
- Mobile capture only runs while the app is in the foreground (OS restriction on background clipboard access). The core mobile scenario is *retrieval*: browse and copy history captured on your other devices.

Build from source instead:

```bash
cd client
flutter pub get
flutter build macos --release   # windows / linux / apk / ipa likewise
```

## Configuration

All settings live in [deploy/config.example.yaml](deploy/config.example.yaml) and can be overridden with `DRIFTCLIP_*` environment variables. The ones that matter most:

| Setting | Notes |
| --- | --- |
| `session_secret` / `key_pepper` | Required strong random values; never commit or log them |
| `server.require_https` | Reject non-HTTPS requests (enable behind a TLS proxy) |
| `server.trusted_proxies` | Proxy CIDRs allowed to set `X-Forwarded-*` headers |
| `history.max_history_records` | Per-account cap (default 1000); lowering it prunes on restart |
| `history.max_clipboard_text_bytes` | Per-record size cap (default 100 KiB) |
| `rate_limit.*` | In-memory sliding-window limits: auth (per IP, 10/min) and upload (per account, 120/min); disable with `enabled: false` |

## Development

Prerequisites: Go 1.26+, Node.js 24+, Flutter 3.44+.

```bash
# Server (API on :8080, serves web/dist when present)
cd server && go run ./cmd/driftclip-server
go test ./... && go vet ./...

# Web (dev server on :5173, proxies /api to :8080)
cd web && npm install && npm run dev
npm run lint && npm test

# Client
cd client && flutter run -d macos
flutter analyze && flutter test
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for the full debugging manual and [docs/CLIPBOARD_SYNC_V1_PLAN.md](docs/CLIPBOARD_SYNC_V1_PLAN.md) for the design and acceptance criteria.

## Contributing & security

- Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
- Found a security issue? Please report privately as described in [SECURITY.md](SECURITY.md); do not open a public issue

## License

[MIT](LICENSE) © JeckChen666
