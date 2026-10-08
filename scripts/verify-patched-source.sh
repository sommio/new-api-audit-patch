#!/usr/bin/env bash
set -euo pipefail

cd "$1"
base_sha=$2
export GOWORK=off
# 只供 Go embed 编译使用；镜像构建仍完整构建真实前端。
mkdir -p web/dist
touch web/dist/index.html
mapfile -d '' -t go_files < <(git diff --name-only -z --diff-filter=ACMR "$base_sha" HEAD -- '*.go')
if [ "${#go_files[@]}" -gt 0 ]; then
  unformatted=$(gofmt -l "${go_files[@]}")
  if [ -n "$unformatted" ]; then
    printf 'ERROR: unformatted Go files:\n%s\n' "$unformatted" >&2
    exit 1
  fi
fi
git diff --check "$base_sha" HEAD
golangci-lint run --timeout=10m --new-from-rev="$base_sha" ./...
go vet ./...
go build ./...
make test
(cd relaykit && go vet ./... && go build ./...)
