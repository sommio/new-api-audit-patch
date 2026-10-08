[English](README.md) | [简体中文](README.zh.md)

# new-api-audit-patch

This repository stores only the audit patch queue and its release automation.
GitHub Actions checks out QuantumNous/new-api in a temporary workspace, applies
`patches/*.patch`, verifies the resulting source, and publishes multi-platform
GHCR images.

Published tags:

- `v*` mirrors an upstream formal release, such as `v1.0.0-rc.25`.
- `latest` points to the newest upstream formal release.
- A seven-character upstream commit SHA, such as `09422fe`, points to that
  specific patched formal release revision.

Deploy by digest, not the moving `latest` tag. Version and short-SHA tags may
also be republished if this patch queue changes.

## Patch maintenance and verification

The current patch base is upstream `v1.0.0-rc.41` (`2035a82aeb5414253a728bd937d4b8f97aa99b9b`), recorded in `UPSTREAM_BASE`. Publishing still follows GitHub's latest non-prerelease Release rather than pinning an older version; `rc` in a tag name is not the GitHub prerelease flag.

Patch, script, and workflow changes in PRs and on main verify both the fixed base and the latest Release. The fixed base checks file blobs after every patch; the latest Release permits legitimate three-way merge changes but must pass the same formatting, full-queue diff lint, vet, build, and test gates. Audit regressions cover role messages for all four protocols, disabled auditing, excluded tokens, streaming, request failures, receiver failures, and request/usage correlation.

Publishing runs the same checks separately on amd64 and arm64 before building images; multi-architecture tags advance only after both succeed. Upstream incompatibility fails closed without skipping patches or downgrading automatically; `latest` retains the last successful release. Deploy by digest and roll back using the previous digest recorded before publishing.

**Coverage limitation:** The upstream Responses WebSocket transport (`GET /v1/responses`) is not yet wired into request auditing: it produces no request/role-message event, and settlement may produce only a usage event. This is not a `raw_only` fallback. The channel option `responses_websocket_enabled` defaults to `false`; deployments requiring complete request auditing must keep it disabled. Role-message support for the four protocols refers to HTTP requests, including SSE responses.

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
