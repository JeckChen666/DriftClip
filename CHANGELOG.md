# Changelog

Notable changes per release. Dates are in UTC.

## [0.1.0] — 2026-09-23

First public release.

### Added

- Go + SQLite server: account registration/login (Argon2id), per-account API keys (shown once, peppered hash at rest), clipboard history API with per-account isolation, retention caps (100 records / 100 KiB per record by default), trusted-proxy + `require_https` enforcement
- React web client: history list with platform/text/time filters, detail view, copy, single/batch delete, clear-all with 5s confirmation, key management, settings
- Flutter native clients for Windows / macOS / Linux / Android / iOS: clipboard monitoring, manual input, history browsing with filters, key-based auth, configurable server address
- Docker Compose deployment and multi-stage Dockerfile
- CI (server/web/client) and release pipeline: multi-platform client builds, server bundles, GHCR image
