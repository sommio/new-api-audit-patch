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

The current patch base is upstream `v1.0.0-rc.44` (`633b4c5b190dc1af99a2814391354d86948e7943`), recorded in `UPSTREAM_BASE`. Publishing still follows GitHub's latest non-prerelease Release rather than pinning an older version; `rc` in a tag name is not the GitHub prerelease flag.

Patch, script, and workflow changes in PRs and on main verify both the fixed base and the latest Release. The fixed base checks file blobs after every patch; the latest Release permits legitimate three-way merge changes but must pass the same formatting, full-queue diff lint, vet, build, and test gates. Audit regressions cover role messages for all four protocols, disabled auditing, excluded tokens, streaming, request failures, receiver failures, and request/usage correlation.

Publishing runs the same checks separately on amd64 and arm64 before building images; multi-architecture tags advance only after both succeed. Upstream incompatibility fails closed without skipping patches or downgrading automatically; `latest` retains the last successful release. Deploy by digest and roll back using the previous digest recorded before publishing.

**Responses WebSocket:** Each `response.create` on `GET /v1/responses` that passes per-request authentication, rate limiting, and format validation produces one independent request event before forwarding. Top-level and nested `response` payloads share the HTTP audit entry point; `request_id` is the per-message ID (within the receiver's 96-character limit), with `request_path=/v1/responses`, `relay_format=openai_responses`, and `is_stream=true`. Requests on one connection remain separate, and channel retries do not duplicate capture. Actual settlement uses the same ID for usage; no usage is fabricated without settlement. Cancel frames, malformed messages, authentication failures, and concurrent-create rejections do not create normal request records. Evidence already captured for an admitted request survives cancellation, disconnect, or upstream failure.

Only input actually submitted by the client in this request is retained. Server history referenced by `previous_response_id` is neither recovered nor inferred, and newly generated response-side content is not separately recorded. Role arrays preserve order; string `input` remains `messages_status=raw_only`, without invented roles. Conversation correlation prefers `Session_id`, then `prompt_cache_key`, both HMAC-derived; no signal means no fabricated conversation ID. The receiver continues to trim tool outputs/results, image base64, and other machine payloads, retaining allowed roles and tool-call `name`/`arguments`. With employee `audit_enabled=false`, request records remain but content is not retained; new employees default to disabled.

Responses `function_call`, `custom_tool_call`, and `reasoning` items can be structured evidence even without `role`; tool-output-only input does not acquire an invented role. Oversized request events compact only `prompt_text`; if `messages` still exceeds the limit, the entire request event is dropped and a later usage event may be the only record.

The accompanying Token Audit receiver no longer stores plaintext `prompt_preview` for newly received `messages_status=available` events, preventing untrimmed flat text from bypassing role filtering, even when all messages are discarded. Compatible previews for `raw_only` are unchanged, and historical previews are not automatically cleaned up. No schema migration is needed, but this privacy fix requires upgrading the audit receiver as well.

The channel option `responses_websocket_enabled` still defaults to `false`; enable it only as needed after deploying a verified image containing this patch. HTTP support for the four protocols and SSE is unchanged. This is not coverage for every WebSocket protocol; `/v1/realtime` is outside this addition. Gateway `AUDIT_ENABLED`, excluded tokens, and the existing single-worker in-memory queue still apply: at-most-once delivery, no retries, no disk persistence. Full queues, oversized events that cannot be compacted, receiver errors, and timeouts can lose events; delivery is not zero-loss and does not block forwarding.

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
