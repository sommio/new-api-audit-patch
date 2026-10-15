# Audit Webhook Contract (External Data Access)

The patched gateway asynchronously POSTs audit events for supported relay paths to `AUDIT_ENDPOINT`. External systems (audit/reporting services) consume data through these two endpoints:

**Responses WebSocket:** Each `response.create` on `GET /v1/responses` that passes per-request authentication, rate limiting, and format validation produces one independent request event before forwarding. Top-level and nested `response` payloads share the HTTP audit entry point; `request_id` is the per-message ID (within the receiver's 96-character limit), with `request_path=/v1/responses`, `relay_format=openai_responses`, and `is_stream=true`. Requests on one connection remain separate, and channel retries do not duplicate capture. Actual settlement uses the same ID for usage; no usage is fabricated without settlement. Cancel frames, malformed messages, authentication failures, and concurrent-create rejections do not create normal request records. Evidence already captured for an admitted request survives cancellation, disconnect, or upstream failure.

Only input actually submitted by the client in this request is retained. Server history referenced by `previous_response_id` is neither recovered nor inferred, and newly generated response-side content is not separately recorded. Role arrays preserve order; string `input` remains `messages_status=raw_only`, without invented roles. Conversation correlation prefers `Session_id`, then `prompt_cache_key`, both HMAC-derived; no signal means no fabricated conversation ID. The receiver continues to trim tool outputs/results, image base64, and other machine payloads, retaining allowed roles and tool-call `name`/`arguments`. With employee `audit_enabled=false`, request records remain but content is not retained; new employees default to disabled.

Responses `function_call`, `custom_tool_call`, and `reasoning` items can be structured evidence even without `role`; tool-output-only input does not acquire an invented role. Oversized request events compact only `prompt_text`; if `messages` still exceeds the limit, the entire request event is dropped and a later usage event may be the only record.

The accompanying Token Audit receiver no longer stores plaintext `prompt_preview` for newly received `messages_status=available` events, preventing untrimmed flat text from bypassing role filtering, even when all messages are discarded. Compatible previews for `raw_only` are unchanged, and historical previews are not automatically cleaned up. No schema migration is needed, but this privacy fix requires upgrading the audit receiver as well.

The channel option `responses_websocket_enabled` still defaults to `false`; enable it only as needed after deploying a verified image containing this patch. HTTP support for the four protocols and SSE is unchanged. This is not coverage for every WebSocket protocol; `/v1/realtime` is outside this addition. Gateway `AUDIT_ENABLED`, excluded tokens, and the existing single-worker in-memory queue still apply: at-most-once delivery, no retries, no disk persistence. Full queues, oversized events that cannot be compacted, receiver errors, and timeouts can lose events; delivery is not zero-loss and does not block forwarding.

| Method | Path | Event |
| --- | --- | --- |
| `POST` | `/internal/new-api/audit/request` | Request metadata and prompt |
| `POST` | `/internal/new-api/audit/usage` | Final token usage and quota |

Each relay request produces at most two events sharing the same `request_id`; arrival order is not guaranteed, and either event may be missing (a request that never reaches billing yields only the request event). Receivers must upsert by `request_id`.

A reference receiver implementation: [new-api-audit-for-company](https://github.com/sommio/new-api-audit-for-company).

## Headers and Signature Verification

```
Content-Type: application/json
X-Audit-Timestamp: <unix seconds at send time>
X-Audit-Signature: hex(hmac_sha256(timestamp + "." + raw_body, AUDIT_SECRET))
```

The signature is computed over the exact raw request body bytes (the precise JSON serialization; no reordering or recompression). Receivers must:

1. Check `X-Audit-Timestamp` is within an acceptable window (suggest 300 seconds; tolerate sender clock skew);
2. Recompute the signature with the shared `AUDIT_SECRET` and compare (constant-time comparison).

Verification example (Python):

```python
import hashlib, hmac

def verify(secret: bytes, body: bytes, timestamp: str, signature: str) -> bool:
    expected = hmac.new(secret, timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)
```

## Request Event Fields

| Field | Type | Description |
| --- | --- | --- |
| `request_id` | string | Gateway request ID; the join key with the usage event |
| `created_at` | string | Event time, RFC3339Nano (UTC) |
| `user_id` | int | User ID |
| `username` | string | Username |
| `user_display_name` | string | User display name (omitted when empty) |
| `token_id` | int | Token ID |
| `token_name` | string | Token name; no event is produced when it matches `AUDIT_EXCLUDED_TOKEN_NAMES` |
| `model_name` | string | Requested model |
| `request_path` | string | Request path |
| `relay_format` | string | Relay protocol format |
| `is_stream` | bool | Whether the request was streaming |
| `prompt_hash` | string | SHA-256 of the prompt text (hex) |
| `prompt_preview` | string | First 500 runes after whitespace collapsing, `...` appended when truncated |
| `prompt_text` | string | Full prompt text; omitted when the event is compacted |
| `prompt_len` | int | Prompt length in runes; present only on compacted events |
| `prompt_omitted` | bool | `true` when the full prompt was omitted |
| `conversation_id` | string | HMAC-derived 64-char hex conversation identifier; omitted when no conversation source exists |
| `conversation_source` | string | `session_id` or `prompt_cache_key`; omitted when no source exists |
| `messages` | JSON array | Original ordered Chat Completions `messages`, Responses and `/v1/responses/compact` `input`, Anthropic Messages structure, or Gemini `contents`. All retain roles, content blocks, tool calls, and preserved unknown message fields. Anthropic and Gemini top-level system instructions are first `{"role":"system","content":...}` entries. Omitted unless `messages_status` is `available` |
| `messages_status` | string | `available` for extractable Chat Completions, Responses or `/v1/responses/compact` input containing roles or `function_call`/`custom_tool_call`/`reasoning` items, Anthropic Messages, or Gemini GenerateContent requests with explicit `user` or `model` roles; `raw_only` for endpoints without a role-message model, Responses input without these structures, Anthropic entries with an unknown role, and Gemini requests with absent or unknown content roles; or `unreadable` when the gateway cannot re-read the validated request body |

`conversation_id` derivation: `hex(hmac_sha256("new-api-audit/conversation\0" + raw, AUDIT_SECRET))`. The raw `Session_id` request header / `prompt_cache_key` value is never sent. Rotating `AUDIT_SECRET` changes the derived ID for the same conversation.

`conversation_source` priority: request header `Session_id` non-empty → `session_id`; otherwise OpenAI Chat `prompt_cache_key` or OpenAI Responses `prompt_cache_key` (a JSON string) → `prompt_cache_key`; otherwise both fields are omitted.

For Chat Completions, the gateway extracts the native request `messages` array before using `CombineText` or converting protocols. For Responses and `/v1/responses/compact`, it extracts the original `input` array before `ParseInput()` and reports the complete array when it contains a role or `function_call`/`custom_tool_call`/`reasoning` item, including unassigned tool-output and non-text items alongside it; the receiver applies retention filtering. For Anthropic Messages, it emits top-level `system` as the first `system` role entry, then preserves native `messages` roles and content structures in order. For Gemini GenerateContent, it emits `systemInstruction` (or accepted `system_instruction`) as the first `system` role entry, then preserves the native `contents` entries in order only when every entry has an explicit `user` or `model` role. These protocols preserve message order and JSON structure rather than deriving roles from flattened text. Endpoints and Responses input without a verifiable role-message model, Anthropic entries with an unknown role, and Gemini requests with absent or unknown content roles send `messages_status=raw_only`; they do not infer a user turn from a Prompt.

## Usage Event Fields

| Field | Type | Description |
| --- | --- | --- |
| `request_id` | string | Gateway request ID; the join key with the request event |
| `created_at` | string | Event time, RFC3339Nano (UTC) |
| `user_id` | int | User ID |
| `username` | string | Username |
| `token_id` | int | Token ID |
| `token_name` | string | Token name |
| `model_name` | string | Requested model |
| `prompt_tokens` | int | Input token count |
| `completion_tokens` | int | Output token count |
| `quota` | int | Quota charged (new-api internal quota units, unconverted) |
| `channel_id` | int | Channel ID |
| `group` | string | Group |
| `use_time_seconds` | int | Duration in seconds |
| `is_stream` | bool | Whether the request was streaming |
| `upstream_request_id` | string | Upstream request ID (may be empty) |

The usage event is emitted when billing is recorded (`RecordConsumeLog`) and is independent of the gateway consume-log toggle (it is still sent when consume logs are disabled).

## Reliability Boundaries

- Delivery is at-most-once: no retries, no persistence. Receivers must tolerate missing events and upsert idempotently by `request_id`.
- Event pairs may be incomplete: request-only (never billed / dropped) or usage-only (e.g. gateway restart).
- Responses ≥400 are only logged; return 2xx.
- Beyond `AUDIT_MAX_EVENT_BYTES`, request events are compacted (see above) and usage events are dropped entirely.

## Privacy and Security

- Full prompts and structured messages travel in plaintext; production must use HTTPS.
- Raw conversation identifiers (`Session_id` header, `prompt_cache_key`) are never sent — only the HMAC-derived value.
- Treat `AUDIT_SECRET` as a credential: after rotation, verification of old events fails and `conversation_id` values change.
