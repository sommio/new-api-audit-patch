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

## License

`patches/*.patch` are derivative works of the AGPL-3.0 upstream
[QuantumNous/new-api](https://github.com/QuantumNous/new-api) and are
distributed under the GNU Affero General Public License v3.0. The remaining
content of this repository is also provided under AGPL-3.0 for simplicity.
See [LICENSE](LICENSE).

The published images contain AGPL-3.0 software. AGPL Section 13 applies to
anyone who deploys them: if you modify the gateway and serve it over a
network, you must make your modified source available under AGPL-3.0.

Complete corresponding source = upstream repository + this patch queue;
rebuild steps are in [docs/en/usage.md](docs/en/usage.md).
