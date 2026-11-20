#!/usr/bin/env bash
# 在当前 skills 仓库安装 post-commit hook（软链到 scripts/hooks/post-commit）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK_SRC="$REPO_ROOT/scripts/hooks/post-commit"
HOOK_DST="$REPO_ROOT/.git/hooks/post-commit"
LINK_TARGET="../../scripts/hooks/post-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "找不到 hook 源脚本: $HOOK_SRC" >&2
  exit 1
fi
chmod +x "$HOOK_SRC"

if [ -L "$HOOK_DST" ]; then
  if [ "$(readlink "$HOOK_DST")" = "$LINK_TARGET" ]; then
    echo "hook 已安装: $HOOK_DST"
    exit 0
  fi
  echo "$HOOK_DST 已指向其它位置，未覆盖；请自行处理后再运行。" >&2
  exit 1
fi
if [ -e "$HOOK_DST" ]; then
  echo "$HOOK_DST 已存在且不是软链，未覆盖；请自行处理后再运行。" >&2
  exit 1
fi

mkdir -p "$(dirname "$HOOK_DST")"
ln -s "$LINK_TARGET" "$HOOK_DST"
echo "已安装 hook: $HOOK_DST -> $LINK_TARGET"
