[English](README.md) | [简体中文](README.zh.md)

# new-api-audit-patch

This repository stores only the audit patch queue and its release automation.
GitHub Actions checks out QuantumNous/new-api in a temporary workspace, applies
`patches/*.patch`, verifies the resulting source, and publishes multi-platform
GHCR images.

Published tags:

- `v*` mirrors an upstream formal release, such as `v1.0.0-rc.25`.
- `latest` points to the newest upstream formal release.
- `main` points to the latest successful build of upstream `main`.
- A seven-character upstream commit SHA, such as `09422fe`, points to that
  specific patched upstream revision.

Deploy by digest, not a moving `latest` or `main` tag. Version and short-SHA
tags may also be republished if this patch queue changes.

## Documentation

- [使用指南 / Usage](docs/zh/usage.md) · [English](docs/en/usage.md) — deploy and configure the patched gateway
- [审计事件契约 / Audit webhook contract](docs/zh/webhook.md) · [English](docs/en/webhook.md) — how external systems receive audit data (endpoints, signature, event fields)
