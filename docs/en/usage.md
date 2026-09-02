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

## Building from Source

The patch queue is based on upstream commit `2d8e50bf` (see `UPSTREAM_BASE`); apply in order:

```bash
git clone https://github.com/QuantumNous/new-api.git upstream
cd upstream && git checkout 2d8e50bf
git am --3way /path/to/patches/*.patch
```

Verify:

```bash
gofmt -l audit controller/relay.go model/log.go model/user.go model/user_cache.go
git diff --check
go test ./audit ./model ./controller
```

## Verifying Audit Is Active

- Gateway logs prefixed with `audit:` (send failures / drops / compactions) indicate audit is enabled.
- The receiver receiving POSTs to `/internal/new-api/audit/request` and `/internal/new-api/audit/usage` confirms the pipeline works.
