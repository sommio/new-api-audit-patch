# Usage Guide

This repository holds only the audit patch queue (`patches/`) and its release automation for [QuantumNous/new-api](https://github.com/QuantumNous/new-api). CI applies the patches in order to upstream source, verifies the result (static checks, unit tests, build), and publishes multi-architecture container images. The images are new-api with the audit patch applied; external audit systems consume data via webhook events (contract: [webhook.md](webhook.md)).

## Images

Published to GHCR:

```
ghcr.io/sommio/new-api-audit-patch
```

| Tag | Points to | Notes |
| --- | --- | --- |
| `latest` | Newest upstream formal release | Moving; updated when upstream releases |
| `v*` | Upstream formal release, e.g. `v1.0.0-rc.25` | Version is fixed; may be republished when the patch queue changes |
| 7-char short SHA (e.g. `09422fe`) | Patched build of that upstream formal release commit | Fixed; may be republished when the patch queue changes |

- Multi-architecture: `linux/amd64` + `linux/arm64`.
- For production, deploy by digest (`docker buildx imagetools inspect ghcr.io/sommio/new-api-audit-patch:<tag>` to resolve it), not by a moving tag.
- CI rebuilds every 6 hours automatically; `workflow_dispatch` triggers manually.

## Deployment

### Environment Variables

| Variable | Default | Required | Description |
| --- | --- | --- | --- |
| `AUDIT_ENABLED` | `false` | Yes | Master switch; `1/true/yes/y/on` count as enabled |
| `AUDIT_ENDPOINT` | empty | Yes | Webhook receiver base URL (trailing `/` is stripped) |
| `AUDIT_SECRET` | empty | Yes | HMAC secret shared with the receiver; used for signature verification and `conversation_id` derivation |
| `AUDIT_TIMEOUT_MS` | `800` | No | Per-request HTTP timeout in milliseconds |
| `AUDIT_QUEUE_SIZE` | `1000` | No | Outbound queue capacity; when full, new events are dropped and logged |
| `AUDIT_MAX_EVENT_BYTES` | `134217728` | No | Per-event size limit in bytes (128 MiB); see "Oversize compaction" |
| `AUDIT_EXCLUDED_TOKEN_NAMES` | empty | No | Comma-separated token names; matching tokens emit no events |

Audit is active only when `AUDIT_ENABLED=true` and both `AUDIT_ENDPOINT` and `AUDIT_SECRET` are non-empty. Otherwise it is fully off and the relay path keeps its zero overhead (no full prompt text is built).

Configuration is read once on first use; restart the container after changing environment variables.

Compose example:

```yaml
services:
  new-api:
    image: ghcr.io/sommio/new-api-audit-patch@sha256:<digest>
    environment:
      AUDIT_ENABLED: "true"
      AUDIT_ENDPOINT: "https://audit.example.com"
      AUDIT_SECRET: "<shared secret, identical on the receiver>"
```

## Behavior

- Async delivery: events enter an in-memory queue and a single background worker POSTs them sequentially; request handling is never blocked.
- At-most-once: full queue, HTTP errors (including ≥400), and timeouts drop the event with a log line — no retry, no persistence. Receivers must tolerate missing events and upsert idempotently by `request_id`.
- Oversize compaction: a request event exceeding `AUDIT_MAX_EVENT_BYTES` is sent without `prompt_text` (`prompt_omitted=true`, plus `prompt_len`, `prompt_hash`, `prompt_preview`); if still too large, it is dropped. Usage events are dropped outright when oversize.
- Exclusion: tokens matching `AUDIT_EXCLUDED_TOKEN_NAMES` emit neither request nor usage events.
- Role-preserved request evidence covers Chat Completions, Responses (including `/v1/responses/compact`), Anthropic Messages, and Gemini GenerateContent. Endpoints without explicit role messages remain `raw_only`; see the [webhook contract](webhook.md).
- Events without a `request_id` are dropped.

**Responses WebSocket:** Each `response.create` on `GET /v1/responses` that passes per-request authentication, rate limiting, and format validation produces one independent request event before forwarding. Top-level and nested `response` payloads share the HTTP audit entry point; `request_id` is the per-message ID (within the receiver's 96-character limit), with `request_path=/v1/responses`, `relay_format=openai_responses`, and `is_stream=true`. Requests on one connection remain separate, and channel retries do not duplicate capture. Actual settlement uses the same ID for usage; no usage is fabricated without settlement. Cancel frames, malformed messages, authentication failures, and concurrent-create rejections do not create normal request records. Evidence already captured for an admitted request survives cancellation, disconnect, or upstream failure.

Only input actually submitted by the client in this request is retained. Server history referenced by `previous_response_id` is neither recovered nor inferred, and newly generated response-side content is not separately recorded. Role arrays preserve order; string `input` remains `messages_status=raw_only`, without invented roles. Conversation correlation prefers `Session_id`, then `prompt_cache_key`, both HMAC-derived; no signal means no fabricated conversation ID. The receiver continues to trim tool outputs/results, image base64, and other machine payloads, retaining allowed roles and tool-call `name`/`arguments`. With employee `audit_enabled=false`, request records remain but content is not retained; new employees default to disabled.

Responses `function_call`, `custom_tool_call`, and `reasoning` items can be structured evidence even without `role`; tool-output-only input does not acquire an invented role. Oversized request events compact only `prompt_text`; if `messages` still exceeds the limit, the entire request event is dropped and a later usage event may be the only record.

The accompanying Token Audit receiver no longer stores plaintext `prompt_preview` for newly received `messages_status=available` events, preventing untrimmed flat text from bypassing role filtering, even when all messages are discarded. Compatible previews for `raw_only` are unchanged, and historical previews are not automatically cleaned up. No schema migration is needed, but this privacy fix requires upgrading the audit receiver as well.

The channel option `responses_websocket_enabled` still defaults to `false`; enable it only as needed after deploying a verified image containing this patch. HTTP support for the four protocols and SSE is unchanged. This is not coverage for every WebSocket protocol; `/v1/realtime` is outside this addition. Gateway `AUDIT_ENABLED`, excluded tokens, and the existing single-worker in-memory queue still apply: at-most-once delivery, no retries, no disk persistence. Full queues, oversized events that cannot be compacted, receiver errors, and timeouts can lose events; delivery is not zero-loss and does not block forwarding.

## Building from Source

The patch queue is based on upstream commit `633b4c5b` (see `UPSTREAM_BASE`); apply in order:

```bash
git clone https://github.com/QuantumNous/new-api.git upstream
cd upstream && git checkout 633b4c5b
git am --3way /path/to/patches/*.patch
```

Patch files are generated with `git format-patch`; do not edit their diff or `index` lines manually. Pull requests and main-branch changes verify both `UPSTREAM_BASE` and the latest upstream formal release. Only the fixed base checks index blobs after every patch; the latest Release permits legitimate three-way merges. Both must pass the full source checks and behavioral tests.

Verify (requires Git, Go, make, and golangci-lint v2.13.1; use Go 1.27.0 to match CI):

```bash
# Run at the patch repository root; upstream is a clean, unpatched checkout.
scripts/test-verify-patch-queue.sh
base_sha=$(git -C upstream rev-parse HEAD)
scripts/verify-patch-queue.sh upstream patches
scripts/verify-patched-source.sh upstream "$base_sha"
```

## Verifying Audit Is Active

- Gateway logs prefixed with `audit:` (send failures / drops / compactions) indicate audit is enabled.
- The receiver receiving POSTs to `/internal/new-api/audit/request` and `/internal/new-api/audit/usage` confirms the pipeline works.
