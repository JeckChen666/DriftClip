# Security Policy

DriftClip is a self-hosted service that stores your clipboard history. Security reports are taken seriously.

## Reporting a vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/JeckChen666/DriftClip/security/advisories/new) for this repository.

Include what you can of: affected component (server / web / native client), version or commit, reproduction steps, and impact. Please do not open a public issue for security problems.

You should receive a first response within a few days. Fixes for confirmed issues are released as soon as practicable and credited in the release notes unless you prefer to stay anonymous.

## Deployment hardening (self-hosters)

- Never expose the server directly to the internet: keep it loopback-only and terminate TLS at a reverse proxy, with `server.require_https` enabled and `server.trusted_proxies` set to your proxy network
- Replace `session_secret` / `key_pepper` with strong random values and store them securely
- Disable registration once your accounts exist (`registration.enabled: false`)
- Backups and disaster recovery are the deployer's responsibility — the SQLite file is the single source of truth
