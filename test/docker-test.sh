#!/usr/bin/env bash
#
# oh-my-linux Docker 测试矩阵（宿主机入口）
#
# 在多个 Debian 系发行版容器中执行安装脚本并验证结果。
# 仓库以只读方式挂载进容器，所有安装行为均发生在容器内部，不影响宿主机。
#
# 用法:
#   ./test/docker-test.sh                     # 默认矩阵: ubuntu:22.04 ubuntu:24.04 debian:12
#   ./test/docker-test.sh ubuntu:24.04        # 仅测试指定镜像
#   ./test/docker-test.sh --full              # 追加 fcitx5 --force 完整安装测试（需容器内联网）

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.tmp/test-logs"
MOUNT_POINT="/opt/oh-my-linux"

DEFAULT_IMAGES=(ubuntu:22.04 ubuntu:24.04 debian:12)
IMAGES=()
FULL_TEST=0

for arg in "$@"; do
  case "$arg" in
    --full)
      FULL_TEST=1
      ;;
    -h|--help)
      sed -n '3,11p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      IMAGES+=("$arg")
      ;;
  esac
done

if [ ${#IMAGES[@]} -eq 0 ]; then
  IMAGES=("${DEFAULT_IMAGES[@]}")
fi

command -v docker >/dev/null 2>&1 || {
  echo "错误：未找到 docker，请先安装 Docker。" >&2
  exit 1
}

mkdir -p "$LOG_DIR"

declare -a RESULTS=()
FAILED=0

echo "========================================================"
echo " oh-my-linux Docker 测试矩阵"
echo " 镜像: ${IMAGES[*]}"
echo " 完整 fcitx5 测试: $([ "$FULL_TEST" = "1" ] && echo 开启 || echo 关闭)"
echo " 日志目录: $LOG_DIR"
echo "========================================================"

for image in "${IMAGES[@]}"; do
  log_file="$LOG_DIR/$(echo "$image" | tr ':/' '__').log"
  echo ""
  echo ">>> [$image] 开始测试（日志: $log_file）"

  if docker run --rm \
    -v "$ROOT_DIR:$MOUNT_POINT:ro" \
    -e OML_TEST_FCITX5="$FULL_TEST" \
    "$image" \
    bash "$MOUNT_POINT/test/inside-container.sh" >"$log_file" 2>&1; then
    echo ">>> [$image] PASS"
    RESULTS+=("PASS  $image")
  else
    echo ">>> [$image] FAIL（详见日志末尾）"
    tail -n 30 "$log_file" | sed 's/^/    | /'
    RESULTS+=("FAIL  $image")
    FAILED=1
  fi
done

echo ""
echo "========================= 结果 ========================="
for line in "${RESULTS[@]}"; do
  echo "  $line"
done
echo "========================================================"

exit "$FAILED"
