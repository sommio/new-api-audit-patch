# 使用指南

本仓库只存放针对 [QuantumNous/new-api](https://github.com/QuantumNous/new-api) 的审计补丁队列（`patches/`）与发布自动化。CI 每次将补丁按序应用到上游源码，通过静态检查、单测与构建后，发布为多架构容器镜像。镜像内即打上审计补丁的 new-api；外部审计系统通过 webhook 事件获取数据（事件契约见 [webhook.md](webhook.md)）。

## 获取镜像

镜像托管于 GHCR：

```
ghcr.io/sommio/new-api-audit-patch
```

| 标签 | 指向 | 说明 |
| --- | --- | --- |
| `latest` | 上游最新正式 release | 移动标签，随上游发版更新 |
| `v*` | 上游正式 release，如 `v1.0.0-rc.25` | 版本号固定；补丁队列更新时可能被重发 |
| 7 位短 SHA（如 `09422fe`） | 对应上游正式 release 提交的 patched 构建 | 固定；补丁队列更新时可能被重发 |

- 多架构：`linux/amd64` + `linux/arm64`。
- 生产建议按 digest 部署（`docker buildx imagetools inspect ghcr.io/sommio/new-api-audit-patch:<tag>` 查 digest），不要追移动标签。
- CI 每 6 小时自动重建一次，也可手动触发 `workflow_dispatch`。

## 部署

### 环境变量

| 变量 | 默认值 | 必填 | 说明 |
| --- | --- | --- | --- |
| `AUDIT_ENABLED` | `false` | 是 | 总开关；`1/true/yes/y/on` 视为开启 |
| `AUDIT_ENDPOINT` | 空 | 是 | webhook 接收端 base URL（末尾 `/` 自动去除） |
| `AUDIT_SECRET` | 空 | 是 | 与接收端共享的 HMAC 密钥，用于验签与 conversation_id 派生 |
| `AUDIT_TIMEOUT_MS` | `800` | 否 | 单次发送 HTTP 超时（毫秒） |
| `AUDIT_QUEUE_SIZE` | `1000` | 否 | 发送队列容量；满则丢弃新事件并记日志 |
| `AUDIT_MAX_EVENT_BYTES` | `134217728` | 否 | 单事件大小上限（字节，128 MiB）；超限行为见"超限压缩" |
| `AUDIT_EXCLUDED_TOKEN_NAMES` | 空 | 否 | 逗号分隔的 token 名称，命中则不发送任何事件 |

开启条件：`AUDIT_ENABLED=true` 且 `AUDIT_ENDPOINT`、`AUDIT_SECRET` 均非空；否则审计完全关闭，中继路径零开销（不构建完整 prompt 文本）。

配置在进程首次使用时读取一次，修改环境变量后必须重启容器。

compose 示例：

```yaml
services:
  new-api:
    image: ghcr.io/sommio/new-api-audit-patch@sha256:<digest>
    environment:
      AUDIT_ENABLED: "true"
      AUDIT_ENDPOINT: "https://audit.example.com"
      AUDIT_SECRET: "<与接收端一致的共享密钥>"
```

## 行为语义

- 异步发送：事件先入内存队列，后台单 worker 顺序 POST，不阻塞请求处理。
- at-most-once：队列满、HTTP 错误（含 ≥400）、超时均丢弃事件，只记日志，不重试、不落盘。接收端必须容忍事件缺失，并按 `request_id` 幂等 upsert。
- 超限压缩：request 事件超过 `AUDIT_MAX_EVENT_BYTES` 时去掉 `prompt_text`（置 `prompt_omitted=true`，附 `prompt_len`、`prompt_hash`、`prompt_preview`）后发送；压缩后仍超限则丢弃。usage 事件超限直接丢弃。
- 排除：命中 `AUDIT_EXCLUDED_TOKEN_NAMES` 的 token 不发 request 也不发 usage 事件。
- 角色保留的请求证据覆盖 Chat Completions、Responses（包括 `/v1/responses/compact`）、Anthropic Messages 和 Gemini GenerateContent。没有明确角色消息的端点保持 `raw_only`；详见 [webhook 契约](webhook.md)。
- 无 `request_id` 的事件直接丢弃。

**覆盖限制：**上游新增的 Responses WebSocket（`GET /v1/responses`）尚未接入请求审计，不生成 request／角色消息事件；结算时可能仅有 usage 事件。这不是 `raw_only` 降级。渠道选项 `responses_websocket_enabled` 默认是 `false`；依赖完整请求审计的部署必须保持关闭。四类协议的角色消息支持指 HTTP 请求（含 SSE 响应）。

## 源码方式使用

补丁队列基于上游提交 `2035a82a`（见 `UPSTREAM_BASE`），按序应用：

```bash
git clone https://github.com/QuantumNous/new-api.git upstream
cd upstream && git checkout 2035a82a
git am --3way /path/to/patches/*.patch
```

补丁文件由 `git format-patch` 生成，不要手工编辑其 diff 或 `index` 行。Pull Request 与 main 分支变更会同时验证 `UPSTREAM_BASE` 和最新上游正式 Release。仅固定基线核对逐补丁 index blob；最新 Release 允许合法三方合并，两者均须通过完整源码检查和行为测试。

验证（需要 Git、Go、make 和 golangci-lint v2.13.1；与 CI 一致使用 Go 1.27.0）：

```bash
# 在补丁仓库根目录运行；upstream 是尚未打补丁的干净上游工作副本。
scripts/test-verify-patch-queue.sh
base_sha=$(git -C upstream rev-parse HEAD)
scripts/verify-patch-queue.sh upstream patches
scripts/verify-patched-source.sh upstream "$base_sha"
```

## 验证审计生效

- 网关日志出现 `audit:` 前缀日志（发送失败/丢弃/压缩）即说明审计开启。
- 接收端收到 POST 到 `/internal/new-api/audit/request` 与 `/internal/new-api/audit/usage` 的事件即链路正常。
