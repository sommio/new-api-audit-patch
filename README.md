# new-api-audit-patch

This repository stores only the audit patch queue and its release automation.
GitHub Actions checks out QuantumNous/new-api in a temporary workspace, applies
`patches/*.patch`, verifies the resulting source, and publishes immutable GHCR
images tagged by upstream commit SHA.

Deploy by digest, not the moving `release` or `main` tags.
