# Contributing to DriftClip

Thanks for your interest in improving DriftClip!

## Getting started

DriftClip is a monorepo with three components:

| Component | Path | Toolchain |
| --- | --- | --- |
| Server | `server/` | Go 1.26+ |
| Web client | `web/` | Node.js 24+ |
| Native clients | `client/` | Flutter 3.44+ |

Set up and run everything locally:

```bash
# Server — API on http://127.0.0.1:8080
cd server && go run ./cmd/driftclip-server

# Web — dev server on http://localhost:5173 (proxies /api to :8080)
cd web && npm install && npm run dev

# Native client (macOS example)
cd client && flutter run -d macos
```

More details (ports, troubleshooting, E2E flows) in [DEVELOPMENT.md](DEVELOPMENT.md).

## Before you open a PR

CI runs the same checks locally available to you — please make sure they pass:

```bash
cd server && go vet ./... && go test ./...
cd web && npm run lint && npm test
cd client && flutter analyze && flutter test
```

Guidelines:

- Keep changes focused; one PR per topic
- New server behavior needs tests (see `server/internal/handler/integration_test.go` for patterns)
- UI changes should respect the shared design tokens (`tokens/tokens.json`)
- Commit messages: conventional style (`feat:`, `fix:`, `docs:`, …); English or Chinese both fine

## Reporting bugs / proposing features

Open an issue using the bug or feature template and fill in the requested details — platform, app version, and reproduction steps matter a lot for a multi-platform app like this one.

## Security issues

Do not open public issues for security problems — see [SECURITY.md](SECURITY.md).
