#!/usr/bin/env bash
set -euo pipefail

upstream_dir=$1
patch_dir=$(cd "$2" && pwd)

for patch in "$patch_dir"/*.patch; do
  git -C "$upstream_dir" am --3way "$patch"

  mapfile -t entries < <(
    awk '
      /^diff --git a\// { path = $4; sub(/^b\//, "", path) }
      /^index [0-9a-f]+\.\.[0-9a-f]+/ {
        split($2, ids, "\\.\\.")
        if (ids[2] != "00000000") print path "\t" ids[2]
      }
    ' "$patch"
  )
  for entry in "${entries[@]}"; do
    IFS=$'\t' read -r path expected <<< "$entry"
    actual=$(git -C "$upstream_dir" rev-parse "HEAD:$path")
    test "${actual:0:${#expected}}" = "$expected"
  done
done
