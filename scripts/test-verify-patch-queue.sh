#!/usr/bin/env bash
set -euo pipefail

# 使用临时 Git 仓库验证真实补丁应用；目录由 CI runner 回收。
script_dir=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
export GIT_AUTHOR_NAME=patch-test GIT_AUTHOR_EMAIL=patch-test@example.invalid
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
mkdir -p "$work/patches" "$work/empty-queue"
git init -q "$work/source"
for n in {1..30}; do echo "line $n"; done > "$work/source/example.txt"
git -C "$work/source" add example.txt
git -C "$work/source" commit -qm base
base=$(git -C "$work/source" rev-parse HEAD)
echo "$base" > "$work/UPSTREAM_BASE"
sed -i '1s/line/patch/' "$work/source/example.txt"
git -C "$work/source" commit -qam patch
git -C "$work/source" format-patch -1 --stdout > "$work/patches/0001.patch"

fresh_tree() {
  git -C "$work/source" worktree add -q --detach "$work/$1" "$base"
}

fresh_tree exact
"$script_dir/verify-patch-queue.sh" "$work/exact" "$work/patches"
test "$(head -1 "$work/exact/example.txt")" = 'patch 1'

fresh_tree forward
sed -i '30s/line/upstream/' "$work/forward/example.txt"
git -C "$work/forward" commit -qam upstream
"$script_dir/verify-patch-queue.sh" "$work/forward" "$work/patches"
test "$(tail -1 "$work/forward/example.txt")" = 'upstream 30'
test "$(head -1 "$work/forward/example.txt")" = 'patch 1'

fresh_tree corrupt
mkdir "$work/bad"
sed -E 's/^(index [0-9a-f]+\.\.)[0-9a-f]+/\111111111/' "$work/patches/0001.patch" > "$work/bad/0001.patch"
if "$script_dir/verify-patch-queue.sh" "$work/corrupt" "$work/bad"; then
  echo 'ERROR: corrupt blob accepted on exact base' >&2; exit 1
fi

fresh_tree empty
if "$script_dir/verify-patch-queue.sh" "$work/empty" "$work/empty-queue"; then
  echo 'ERROR: empty queue accepted' >&2; exit 1
fi

fresh_tree conflict
sed -i '1s/line/conflict/' "$work/conflict/example.txt"
git -C "$work/conflict" commit -qam conflict
if "$script_dir/verify-patch-queue.sh" "$work/conflict" "$work/patches"; then
  echo 'ERROR: conflicting patch accepted' >&2; exit 1
fi

# 删除文件的零 blob（不同 Git 哈希长度）不能当作 HEAD 中的文件读取。
git -C "$work/source" mv example.txt moved.txt
git -C "$work/source" commit -qm rename
# --no-renames 生成独立的删除和新增条目。
git -C "$work/source" format-patch -1 --no-renames --stdout > "$work/patches/0002.patch"
fresh_tree deletion
"$script_dir/verify-patch-queue.sh" "$work/deletion" "$work/patches"
test ! -e "$work/deletion/example.txt"
test -f "$work/deletion/moved.txt"
echo 'PASS: exact base, forward compatibility, corrupt blob, empty queue, conflict, deletion'

# 第一个补丁的格式错误不能被最后三个提交的检查范围漏掉。
fresh_tree full-range
printf 'package example\nfunc example( ) { }\n' > "$work/full-range/example.go"
git -C "$work/full-range" add example.go
git -C "$work/full-range" commit -qm 'first patch is unformatted'
for n in 2 3 4; do
  echo "$n" >> "$work/full-range/example.txt"
  git -C "$work/full-range" commit -qam "patch $n"
done
if "$script_dir/verify-patched-source.sh" "$work/full-range" "$base" > "$work/format.log" 2>&1; then
  echo 'ERROR: early formatting regression accepted' >&2; exit 1
fi
case "$(cat "$work/format.log")" in
  *'ERROR: unformatted Go files:'*'example.go'*) ;;
  *) cat "$work/format.log"; exit 1 ;;
esac
echo 'PASS: source verification covers the full patch range'
