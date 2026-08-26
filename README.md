# new-api-audit-patch

This repository stores only the audit patch queue and its release automation.
GitHub Actions checks out QuantumNous/new-api in a temporary workspace, applies
`patches/*.patch`, verifies the resulting source, and publishes multi-platform
GHCR images.

Published tags:

- `v*` mirrors an upstream formal release, such as `v1.0.0-rc.25`.
- `latest` points to the newest upstream formal release.
- `main` points to the latest successful build of upstream `main`.
- A seven-character upstream commit SHA, such as `09422fe`, points to that
  specific patched upstream revision.

Deploy by digest, not a moving `latest` or `main` tag. Version and short-SHA
tags may also be republished if this patch queue changes.
