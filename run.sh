#!/usr/bin/env bash
# oh-my-linux 统一入口：安装终端 / 输入法、更新子模块、生成离线包。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
用法:
  ./run.sh install terminal [选项]
  ./run.sh install im [选项]
  ./run.sh update
  ./run.sh create

命令:
  install terminal  安装 Zsh + Oh My Zsh + Powerlevel10k + 插件 + Tmux
  install im        安装 fcitx5 + Rime 输入法（无图形会话时自动跳过）
  update            更新子模块到远端最新提交（指针变更需自行提交）
  create            生成离线包：dist/oh-my-linux_YYYYMMDD.tar.gz

安装选项:
  -y, --unattended   无人值守安装
  -f, --force        跳过图形会话检测（仅 install im）
  -h, --help         查看帮助，也可在具体安装命令后使用

示例:
  ./run.sh install terminal --unattended
  ./run.sh install im --force
EOF
}

fail() {
  printf '错误：%s（使用 ./run.sh --help 查看帮助）\n' "$1" >&2
  exit 1
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    install)
      shift
      local component="${1:-}"
      case "$component" in
        terminal|im)
          shift
          exec bash "$ROOT_DIR/script/install-$component.sh" "$@"
          ;;
        -h|--help)
          usage
          ;;
        "")
          fail "请指定安装目标：terminal 或 im"
          ;;
        *)
          fail "未知安装目标：$component（可选 terminal / im）"
          ;;
      esac
      ;;
    update|create)
      exec bash "$ROOT_DIR/script/maintain.sh" "$@"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      fail "未知命令：$cmd"
      ;;
  esac
}

main "$@"
