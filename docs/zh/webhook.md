# 审计事件契约（外部数据获取）

打补丁后的网关将每个中继请求的审计事件异步 POST 到 `AUDIT_ENDPOINT`，外部系统（审计/报表服务）通过这两个端点获取数据：

| Method | 路径 | 事件 |
| --- | --- | --- |
| `POST` | `/internal/new-api/audit/request` | 请求元数据与 prompt |
| `POST` | `/internal/new-api/audit/usage` | 最终用量与扣费 |

每个中继请求按同一 `request_id` 最多产生两条事件；两者到达顺序不保证，且可能只到达一条（请求未走到计费时只有 request 事件）。接收端按 `request_id` upsert 关联。

参考接收端实现：[new-api-audit-for-company](https://github.com/sommio/new-api-audit-for-company)。

## 请求头与验签

```
Content-Type: application/json
X-Audit-Timestamp: <unix 秒，发送时刻>
X-Audit-Signature: hex(hmac_sha256(timestamp + "." + raw_body, AUDIT_SECRET))
```

签名对象是原始请求体字节（JSON 序列化后的精确字节，不做重排或压缩）。接收端必须：

1. 校验 `X-Audit-Timestamp` 在可接受时间窗口内（建议 300 秒，容忍发送方时钟偏差）；
2. 用共享 `AUDIT_SECRET` 按上述公式重算签名并比对（constant-time 比较）。

验签示例（Python）：

```python
import hashlib, hmac

def verify(secret: bytes, body: bytes, timestamp: str, signature: str) -> bool:
    expected = hmac.new(secret, timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)
```

## request 事件字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `request_id` | string | 网关请求 ID，与 usage 事件关联的键 |
| `created_at` | string | 事件产生时刻，RFC3339Nano（UTC） |
| `user_id` | int | 用户 ID |
| `username` | string | 用户名 |
| `user_display_name` | string | 用户显示名（为空时省略） |
| `token_id` | int | token ID |
| `token_name` | string | token 名称；命中 `AUDIT_EXCLUDED_TOKEN_NAMES` 时不产生事件 |
| `model_name` | string | 请求模型 |
| `request_path` | string | 请求路径 |
| `relay_format` | string | 中继协议格式 |
| `is_stream` | bool | 是否流式 |
| `prompt_hash` | string | prompt 文本 SHA-256（hex） |
| `prompt_preview` | string | 空白折叠后的前 500 个字符（rune），截断时加 `...` |
| `prompt_text` | string | 完整 prompt 文本；超限压缩时省略 |
| `prompt_len` | int | prompt 字符数（rune 计数）；仅超限压缩时出现 |
| `prompt_omitted` | bool | 为 `true` 表示完整 prompt 被省略 |
| `conversation_id` | string | HMAC 派生的 64 位 hex 会话标识；无会话来源时省略 |
| `conversation_source` | string | `session_id` 或 `prompt_cache_key`；无来源时省略 |
| `messages` | JSON 数组 | 原始、有序的 Chat Completions `messages` 或 Responses `input` 数组，保留角色、内容块、工具调用和可保留的未知消息字段；仅当 `messages_status` 为 `available` 时出现 |
| `messages_status` | string | 可提取的 Chat Completions 或含明确角色的 Responses input 为 `available`；没有可确定角色的端点或 Responses input 为 `raw_only`；网关无法重读已验证请求体时为 `unreadable` |

`conversation_id` 派生：`hex(hmac_sha256("new-api-audit/conversation\0" + raw, AUDIT_SECRET))`。原始 `Session_id` 请求头 / `prompt_cache_key` 值绝不外发；轮换 `AUDIT_SECRET` 后同一会话的派生 ID 会变化。

`conversation_source` 取值优先级：请求头 `Session_id` 非空 → `session_id`；否则 OpenAI Chat 请求的 `prompt_cache_key`、OpenAI Responses 请求的 `prompt_cache_key`（JSON 字符串）→ `prompt_cache_key`；都没有则不产生这两个字段。

对于 Chat Completions，网关在使用 `CombineText` 或转换协议前提取原生请求 `messages` 数组。对于 Responses，网关在 `ParseInput()` 前提取原始 `input` 数组；只要数组含有明确角色，就完整保留该数组，包括其中无角色的工具输出和非文本项。两者均保留消息顺序和 JSON 结构，不从扁平文本推断角色。没有可验证角色消息模型的端点，以及没有可确定角色的 Responses input，发送 `messages_status=raw_only`，不会把 Prompt 猜作用户轮次。

## usage 事件字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `request_id` | string | 网关请求 ID，与 request 事件关联的键 |
| `created_at` | string | 事件产生时刻，RFC3339Nano（UTC） |
| `user_id` | int | 用户 ID |
| `username` | string | 用户名 |
| `token_id` | int | token ID |
| `token_name` | string | token 名称 |
| `model_name` | string | 请求模型 |
| `prompt_tokens` | int | 输入 token 数 |
| `completion_tokens` | int | 输出 token 数 |
| `quota` | int | 扣费额度（new-api 内部额度单位，不换算） |
| `channel_id` | int | 渠道 ID |
| `group` | string | 分组 |
| `use_time_seconds` | int | 耗时（秒） |
| `is_stream` | bool | 是否流式 |
| `upstream_request_id` | string | 上游请求 ID（可为空） |

usage 事件在计费（`RecordConsumeLog`）时产生，与网关"消费日志"开关无关（关闭消费日志仍发送）。

## 可靠性边界

- 发送为 at-most-once：不重试、不持久化。接收端必须容忍事件缺失，并按 `request_id` 幂等 upsert。
- 事件对可能不完整：只有 request（未计费/被丢弃），或只有 usage（如网关重启）。
- 响应 ≥400 仅记日志；请返回 2xx。
- 超过 `AUDIT_MAX_EVENT_BYTES` 时，request 事件压缩后发送，usage 事件整体丢弃。

## 隐私与安全

- 完整 prompt 与结构化消息以明文 POST 传输，生产环境必须走 HTTPS。
- 原始会话标识（`Session_id` 头、`prompt_cache_key`）永不外发，只发 HMAC 派生值。
- `AUDIT_SECRET` 是签名与派生密钥，按凭据管理：轮换后旧事件验签失败、`conversation_id` 变化。
