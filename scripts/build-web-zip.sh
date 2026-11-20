#!/usr/bin/env bash
# 生成供官网分发的 skill zip：把 skills/aitestui/ 打包成顶层 aitestui/ 目录的 zip。
# 用法：bash scripts/build-web-zip.sh <fe_aitestui/public/skills 目录的绝对路径> [skill 源目录]
# 例：  bash scripts/build-web-zip.sh /Users/yfj/code/h5qa/fe_aitestui/public/skills
# 第二个参数供 post-commit hook 传入从 HEAD 导出的临时目录，确保 zip 只含已提交内容。
set -euo pipefail

OUT_DIR="${1:-}"
if [ -z "$OUT_DIR" ]; then
  echo "用法: bash scripts/build-web-zip.sh <public/skills 目录> [skill 源目录]" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${2:-$REPO_ROOT/skills/aitestui}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/aitestui"
cp -R "$SRC_DIR/." "$TMP/aitestui/"

# 排除本地登录态与运行产物（若误入）
rm -rf "$TMP/aitestui/.auth" "$TMP/aitestui/output" "$TMP/aitestui/.h5qa-runs"

OUT="$OUT_DIR/aitestui.zip"
(cd "$TMP" && zip -rq "$OUT" aitestui)
echo "已生成: $OUT"
unzip -l "$OUT"
