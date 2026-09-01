# Audit Webhook Contract (External Data Access)

The patched gateway asynchronously POSTs audit events for every relay request to `AUDIT_ENDPOINT`. External systems (audit/reporting services) consume data through these two endpoints:

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
| `messages` | JSON array | Original ordered Chat Completions `messages` array, including roles, content blocks, tool calls, and preserved unknown message fields; omitted unless `messages_status` is `available` |
| `messages_status` | string | `available` for extractable Chat Completions messages, `raw_only` for endpoints without role messages, or `unreadable` when the gateway cannot re-read the validated request body |

`conversation_id` derivation: `hex(hmac_sha256("new-api-audit/conversation\0" + raw, AUDIT_SECRET))`. The raw `Session_id` request header / `prompt_cache_key` value is never sent. Rotating `AUDIT_SECRET` changes the derived ID for the same conversation.

`conversation_source` priority: request header `Session_id` non-empty → `session_id`; otherwise OpenAI Chat `prompt_cache_key` or OpenAI Responses `prompt_cache_key` (a JSON string) → `prompt_cache_key`; otherwise both fields are omitted.

For Chat Completions, the gateway extracts the native request `messages` array before using `CombineText` or converting protocols. It preserves message order and JSON structure rather than deriving roles from flattened text. Endpoints without a verifiable role-message model send `messages_status=raw_only`; they do not infer a user turn from a Prompt.

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
