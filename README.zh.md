[English](README.md) | [简体中文](README.zh.md)

# new-api-audit-patch

本仓库只存放审计补丁队列及其发布自动化。GitHub Actions 在临时工作区检出 QuantumNous/new-api，应用 `patches/*.patch`，验证结果源码，并发布多架构 GHCR 镜像。

已发布标签：

- `v*` 镜像上游正式 release，如 `v1.0.0-rc.25`。
- `latest` 指向最新的上游正式 release。
- 7 位上游提交 SHA，如 `09422fe`，指向该特定 patched 正式 release 修订。

请按 digest 部署，不要追 `latest` 移动标签。补丁队列变更时，版本号与短 SHA 标签也可能被重发。

## 补丁维护与验证

当前补丁基线是上游 `v1.0.0-rc.41`（`2035a82aeb5414253a728bd937d4b8f97aa99b9b`），见 `UPSTREAM_BASE`。发布流程仍跟进 GitHub 标记的最新非预发布 Release，不固定到旧版本；标签名包含 `rc` 不等于 GitHub 的 prerelease 标记。

PR 与 main 分支的补丁、脚本、workflow 变更会验证固定基线和最新 Release：固定基线逐补丁核对文件 blob；最新 Release 允许合法的三方合并变化，但必须通过同一套格式、完整补丁差异 lint、vet、构建和测试。审计回归覆盖四类协议的角色消息，以及审计关闭、Token 排除、流式、请求失败、接收端失败和请求/用量关联。

发布流程对 amd64、arm64 分别执行相同检查后构建镜像；两者成功后才更新多架构标签。上游不兼容时失败退出，不跳过补丁、不自动降级；`latest` 保留最近一次成功发布。部署仍须使用 digest，回滚时使用发布前记录的旧 digest。

**覆盖限制：**上游新增的 Responses WebSocket（`GET /v1/responses`）尚未接入请求审计，不生成 request／角色消息事件；结算时可能仅有 usage 事件。这不是 `raw_only` 降级。渠道选项 `responses_websocket_enabled` 默认是 `false`；依赖完整请求审计的部署必须保持关闭。四类协议的角色消息支持指 HTTP 请求（含 SSE 响应）。

## 文档

- [使用指南](docs/zh/usage.md) — 部署与配置 patched 网关
- [审计事件契约](docs/zh/webhook.md) — 外部系统如何获取审计数据（端点、验签、事件字段）

英文版：[usage](docs/en/usage.md) · [webhook](docs/en/webhook.md)

## 许可证

`patches/*.patch` 是 AGPL-3.0 上游 [QuantumNous/new-api](https://github.com/QuantumNous/new-api) 的衍生作品，以 GNU Affero General Public License v3.0 分发。本仓库其余内容同样统一以 AGPL-3.0 提供。见 [LICENSE](LICENSE)。

已发布镜像包含 AGPL-3.0 软件，部署者受 AGPL 第 13 节约束：若修改网关并对外提供网络服务，必须以 AGPL-3.0 公开你的修改源码。

完整对应源码 = 上游仓库 + 本补丁队列；重建步骤见 [docs/zh/usage.md](docs/zh/usage.md)。
