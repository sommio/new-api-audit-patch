#!/usr/bin/env bash
set -euo pipefail

upstream_dir=$1
patch_dir=$(cd "$2" && pwd)
base_sha=$(git -C "$upstream_dir" rev-parse HEAD)
expected_base=$(cat "$patch_dir/../UPSTREAM_BASE")

if [ -n "$(git -C "$upstream_dir" status --porcelain --untracked-files=no)" ]; then
  echo 'ERROR: upstream has uncommitted changes' >&2
  exit 1
fi
shopt -s nullglob
patches=("$patch_dir"/*.patch)
if [ "${#patches[@]}" -eq 0 ]; then
  echo 'ERROR: patch queue is empty' >&2
  exit 1
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "base_sha=$base_sha" >> "$GITHUB_OUTPUT"
fi

for patch in "${patches[@]}"; do
  git -C "$upstream_dir" am --3way "$patch"

  # blob 是固定基线的产物；新上游允许保留三方合并带来的合法变化。
  # 最新 Release 的兼容性由同一入口之后的源码、行为及构建检查保证。
  if [ "$base_sha" != "$expected_base" ]; then
    continue
  fi
  mapfile -t entries < <(
    awk '
      /^diff --git a\// { path = $4; sub(/^b\//, "", path) }
      /^index [0-9a-f]+\.\.[0-9a-f]+/ {
        split($2, ids, "\\.\\.")
        if (ids[2] !~ /^0+$/) print path "\t" ids[2]
      }
    ' "$patch"
  )
  for entry in "${entries[@]}"; do
    IFS=$'\t' read -r path expected <<< "$entry"
    actual=$(git -C "$upstream_dir" rev-parse "HEAD:$path")
    if [ "${actual:0:${#expected}}" != "$expected" ]; then
      echo "ERROR: blob mismatch in $patch: $path (expected $expected, got $actual)" >&2
      exit 1
    fi
  done
done

git -C "$upstream_dir" diff --check "$base_sha" HEAD
