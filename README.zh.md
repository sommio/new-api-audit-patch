[English](README.md) | [简体中文](README.zh.md)

# new-api-audit-patch

本仓库只存放审计补丁队列及其发布自动化。GitHub Actions 在临时工作区检出 QuantumNous/new-api，应用 `patches/*.patch`，验证结果源码，并发布多架构 GHCR 镜像。

已发布标签：

- `v*` 镜像上游正式 release，如 `v1.0.0-rc.25`。
- `latest` 指向最新的上游正式 release。
- `main` 指向上游 `main` 分支的最新成功构建。
- 7 位上游提交 SHA，如 `09422fe`，指向该特定 patched 上游修订。

请按 digest 部署，不要追 `latest` 或 `main` 移动标签。补丁队列变更时，版本号与短 SHA 标签也可能被重发。

## 文档

- [使用指南](docs/zh/usage.md) — 部署与配置 patched 网关
- [审计事件契约](docs/zh/webhook.md) — 外部系统如何获取审计数据（端点、验签、事件字段）

英文版：[usage](docs/en/usage.md) · [webhook](docs/en/webhook.md)
