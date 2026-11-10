#!/usr/bin/env bash
# 无需 Docker / 网络 / sudo 的统一入口测试，不执行真实安装。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$ROOT_DIR/run.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PASS_COUNT=0

check() {
  local expected_status="$1" expected_output="$2"
  shift 2
  local status=0 output
  output="$("$@" 2>&1)" || status=$?
  if [ "$status" -ne "$expected_status" ] || [[ "$output" != *"$expected_output"* ]]; then
    printf '[FAIL] %s\n退出码: %s（预期 %s）\n%s\n' "$*" "$status" "$expected_status" "$output" >&2
    exit 1
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[ok] %s\n' "$*"
}

# 从其他目录执行，确保所有路径均相对脚本自身解析。
cd "$TMP_DIR"
check 0 'install terminal' "$ENTRY"
check 0 'install im' "$ENTRY" --help
check 0 'install terminal' "$ENTRY" install --help
check 0 '用法: ./run.sh install terminal' "$ENTRY" install terminal --help
check 0 '用法: ./run.sh install im' "$ENTRY" install im --help
check 1 '请指定安装目标' "$ENTRY" install
check 1 '未知命令' "$ENTRY" unknown
check 1 '未知安装目标' "$ENTRY" install unknown
check 1 '未知参数' "$ENTRY" install terminal --unknown
check 1 '未知参数' "$ENTRY" install im --unknown
check 1 '不接受额外参数' "$ENTRY" update unexpected
check 1 '不接受额外参数' "$ENTRY" create unexpected

# 无图形会话应立即跳过；即使临时目录不可用，也不应创建任何文件。
mkdir "$TMP_DIR/home"
check 0 '跳过 fcitx5' env \
  -u XDG_CURRENT_DESKTOP -u DESKTOP_SESSION -u WAYLAND_DISPLAY -u DISPLAY \
  HOME="$TMP_DIR/home" TMPDIR="$TMP_DIR/nonexistent" \
  "$ENTRY" install im --unattended
check 0 '' test -z "$(find "$TMP_DIR/home" -mindepth 1 -print -quit)"

# 用替身安装器验证参数原样转发、环境继承与退出码传播，不触碰宿主机配置。
MOCK_ROOT="$TMP_DIR/mock project"
mkdir -p "$MOCK_ROOT/script"
cp "$ENTRY" "$MOCK_ROOT/run.sh"
cat > "$MOCK_ROOT/script/install-terminal.sh" <<'EOF'
#!/usr/bin/env bash
printf 'env=<%s>\n' "${OML_CLI_TEST:-}"
printf 'arg=<%s>\n' "$@"
exit 23
EOF
cp "$MOCK_ROOT/script/install-terminal.sh" "$MOCK_ROOT/script/install-im.sh"
cp "$MOCK_ROOT/script/install-terminal.sh" "$MOCK_ROOT/script/maintain.sh"
check 23 $'env=<inherited>\narg=<--unattended>\narg=<two words>' \
  env OML_CLI_TEST=inherited "$MOCK_ROOT/run.sh" install terminal --unattended 'two words'
check 23 $'arg=<--force>\narg=<--unattended>' \
  "$MOCK_ROOT/run.sh" install im --force --unattended
check 23 'arg=<update>' "$MOCK_ROOT/run.sh" update
check 23 'arg=<create>' "$MOCK_ROOT/run.sh" create

# 解压后的离线包没有 .git，维护命令应给出明确提示而非尝试操作 Git。
cp "$ROOT_DIR/script/maintain.sh" "$ROOT_DIR/script/common.sh" "$MOCK_ROOT/script/"
check 1 '仅适用于 Git 仓库' "$MOCK_ROOT/run.sh" update
check 1 '请在 Git 仓库中执行' "$MOCK_ROOT/run.sh" create

printf '\nCLI 测试通过 %s 项\n' "$PASS_COUNT"
