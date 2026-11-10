#!/usr/bin/env bash
# oh-my-linux 公共函数库
#
# 由各安装/维护脚本 source 使用，调用方可预先设置以下变量：
#   PROGRESS_FILE   步骤进度文件路径（使用 is_step_done/mark_step_* 时必需）
#   LOG_FILE        日志文件路径（未设置则仅输出到终端）
#   OML_UNATTENDED  置 1 时 confirm() 直接采用默认值，不再交互
#
# 本文件中的变量（颜色、SUDO、OML_RIME_ICE_*）属于对外 API，供 source 方使用。
# shellcheck disable=SC2034

# 防止重复加载
if [ -n "${OML_COMMON_LOADED:-}" ]; then
  return 0
fi
OML_COMMON_LOADED=1

# rime-ice 词库版本（输入法安装与离线打包共用同一处定义）
OML_RIME_ICE_VERSION="2024.05.21"
OML_RIME_ICE_URL="https://github.com/iDvel/rime-ice/archive/refs/tags/${OML_RIME_ICE_VERSION}.zip"

RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
RESET='\e[0m'

# 非 root 用户执行系统级命令时需要 sudo
SUDO=''
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  SUDO='sudo'
fi

# ======== 日志 ========

log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  if [ -n "${LOG_FILE:-}" ]; then
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
  else
    echo -e "[$timestamp] [$level] $message"
  fi
}

info() { log "INFO" "${BLUE}$1${RESET}"; }
warn() { log "WARN" "${YELLOW}$1${RESET}"; }
error() { log "ERROR" "${RED}$1${RESET}"; }
success() { log "SUCCESS" "${GREEN}$1${RESET}"; }

die() {
  error "$1"
  exit 1
}

command_exists() {
  command -v "$1" &>/dev/null
}

# ======== 步骤进度（可重入支持） ========

is_step_done() {
  [ -f "${PROGRESS_FILE:-}" ] || return 1
  grep -q "^$1=done$" "$PROGRESS_FILE"
}

mark_step_done() {
  if ! grep -q "^$1=" "$PROGRESS_FILE" 2>/dev/null; then
    echo "$1=done" >> "$PROGRESS_FILE"
  else
    sed -i "s/^$1=.*/$1=done/" "$PROGRESS_FILE"
  fi
}

mark_step_in_progress() {
  if ! grep -q "^$1=" "$PROGRESS_FILE" 2>/dev/null; then
    echo "$1=in_progress" >> "$PROGRESS_FILE"
  else
    sed -i "s/^$1=.*/$1=in_progress/" "$PROGRESS_FILE"
  fi
}

step_start() {
  info "开始: $1"
  echo -e "\n${MAGENTA}=== $1 ===${RESET}"
}

step_done() {
  success "$1 完成"
  echo -e "${GREEN}✓ $1 完成${RESET}\n"
}

# ======== 交互确认 ========

# confirm "提示语" "默认值(y|n)"
# 无人值守模式（OML_UNATTENDED=1）或 stdin 非终端时直接采用默认值。
confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local reply

  if [ "${OML_UNATTENDED:-0}" = "1" ] || [ ! -t 0 ]; then
    info "非交互模式，自动选择 '$default'：$prompt"
    [ "$default" = "y" ]
    return
  fi

  read -r -p "$prompt (y/n) [$default]: " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# ======== 系统检查 ========

# 校验当前系统为 Debian 系（ID 或 ID_LIKE 含 debian/ubuntu），否则退出。
# 成功后导出 OS_ID / OS_NAME / OS_VERSION_ID。
require_debian_family() {
  [ -r /etc/os-release ] || die "未找到 /etc/os-release，无法判断发行版"

  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_NAME="${NAME:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-}"
  export OS_ID OS_NAME OS_VERSION_ID

  local family=" ${ID:-} ${ID_LIKE:-} "
  case "$family" in
    *" debian "* | *" ubuntu "*)
      info "检测到操作系统: ${PRETTY_NAME:-$OS_NAME}"
      ;;
    *)
      die "仅支持 Debian 系发行版（Debian/Ubuntu 及其衍生版），当前系统：${PRETTY_NAME:-unknown}"
      ;;
  esac
}

# 检测当前是否处于图形会话（用于决定是否安装输入法等桌面组件）
has_graphical_session() {
  [ -n "${XDG_CURRENT_DESKTOP:-}" ] || [ -n "${DESKTOP_SESSION:-}" ] ||
    [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]
}
