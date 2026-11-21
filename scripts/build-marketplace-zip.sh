#!/usr/bin/env bash
# 生成供 WorkBuddy 技能市场上传的 zip：解压后第一层直接是 SKILL.md（不套 aitestui/ 目录）。
# 这与官网/skills.sh 的 zip 结构相反——那边要求顶层 aitestui/ 目录，别混用。
# 用法：bash scripts/build-marketplace-zip.sh <输出目录> [skill 源目录]
set -euo pipefail

OUT_DIR="${1:-}"
if [ -z "$OUT_DIR" ]; then
  echo "用法: bash scripts/build-marketplace-zip.sh <输出目录> [skill 源目录]" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${2:-$REPO_ROOT/skills/aitestui}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$SRC_DIR/." "$TMP/"

# 排除本地登录态与运行产物（若误入）
rm -rf "$TMP/.auth" "$TMP/output" "$TMP/.h5qa-runs"

OUT="$OUT_DIR/aitestui-workbuddy-market.zip"
(cd "$TMP" && zip -rq "$OUT" SKILL.md references scripts)
echo "已生成: $OUT"
unzip -l "$OUT"
