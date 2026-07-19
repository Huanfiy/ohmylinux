#!/usr/bin/env bash
#
# 使用 shellcheck（Docker 镜像，不依赖宿主机安装）静态检查本项目全部 shell 脚本。
#
# 用法: ./test/lint.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v docker >/dev/null 2>&1 || {
  echo "错误：未找到 docker，请先安装 Docker。" >&2
  exit 1
}

SCRIPTS=(
  install_zsh_tmux.sh
  install_fcitx5_rime.sh
  run.sh
  lib/common.sh
  test/docker-test.sh
  test/inside-container.sh
  test/lint.sh
)

echo "shellcheck 检查: ${SCRIPTS[*]}"
docker run --rm -v "$ROOT_DIR:/mnt:ro" -w /mnt \
  koalaman/shellcheck:stable --severity=warning --external-sources "${SCRIPTS[@]}"
echo "shellcheck 通过"
