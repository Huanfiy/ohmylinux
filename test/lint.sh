#!/usr/bin/env bash
#
# 使用 shellcheck 静态检查全部自有 shell 脚本；本机未安装时回退到 Docker。
#
# 用法: ./test/lint.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
SCRIPTS=(run.sh script/*.sh test/*.sh)

echo "shellcheck 检查: ${SCRIPTS[*]}"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=warning --external-sources "${SCRIPTS[@]}"
else
  command -v docker >/dev/null 2>&1 || {
    echo "错误：请安装 shellcheck 或 Docker。" >&2
    exit 1
  }
  docker run --rm -v "$ROOT_DIR:/mnt:ro" -w /mnt \
    koalaman/shellcheck:stable --severity=warning --external-sources "${SCRIPTS[@]}"
fi
echo "shellcheck 通过"
