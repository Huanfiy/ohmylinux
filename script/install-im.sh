#!/usr/bin/env bash
#
# oh-my-linux · fcitx5 + Rime 中文输入法安装脚本
#
# 功能：安装 fcitx5、fcitx5-rime，配置 rime-ice 词库与 Alpha-white 候选框主题
# 支持：Debian 系发行版（主要验证于 Ubuntu 22.04/24.04），仅限图形桌面环境
# 说明：无图形会话（服务器/容器/SSH）时自动跳过安装，可用 --force 强制执行
#
# 用法：
#   ./run.sh install im                # 常规安装
#   ./run.sh install im --force        # 跳过图形会话检测强制安装
#   SUDO_PASSWORD=xxx ./run.sh install im   # 免交互提供 sudo 密码

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=script/common.sh
source "$ROOT_DIR/script/common.sh"

FORCE_INSTALL=0
SUDO_PASSWORD="${SUDO_PASSWORD:-}"
HOME_DIR="${HOME:-}"
AUTOSTART_DIR="${HOME_DIR}/.config/autostart"
AUTOSTART_FILE="${AUTOSTART_DIR}/org.fcitx.Fcitx5.desktop"
RIME_DIR="${HOME_DIR}/.local/share/fcitx5/rime"
THEME_DIR="${HOME_DIR}/.local/share/fcitx5/themes"
THEME_NAME="Alpha-white"
XPROFILE_FILE="${HOME_DIR}/.xprofile"
ENVD_FILE="${HOME_DIR}/.config/environment.d/95-fcitx5.conf"
TMP_DIR=""
RIME_ZIP_LOCAL="${ROOT_DIR}/resources/rime-ice-${OML_RIME_ICE_VERSION}.zip"
PACKAGES=(
  fcitx5
  fcitx5-chinese-addons
  fcitx5-rime
  fcitx5-frontend-gtk3
  fcitx5-frontend-gtk4
  fcitx5-frontend-qt5
  im-config
  wget
  unzip
)

cleanup() {
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
用法: ./run.sh install im [选项]

选项:
  -y, --unattended   无人值守模式（本脚本无交互确认，仅保持与其他脚本一致的入口）
  -f, --force        跳过图形会话检测，强制执行安装
  -h, --help         显示本帮助

环境变量:
  SUDO_PASSWORD      预先提供 sudo 密码，避免交互输入
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--unattended)
        OML_UNATTENDED=1
        ;;
      -f|--force)
        FORCE_INSTALL=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "未知参数: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}

check_environment() {
  step_start "检查安装环境"

  [[ -n "${HOME_DIR}" && -d "${HOME_DIR}" && -w "${HOME_DIR}" ]] || \
    die "当前 HOME 不存在或不可写：${HOME_DIR:-未设置}"

  require_debian_family

  if [[ "${OS_ID}" == "ubuntu" ]]; then
    case "${OS_VERSION_ID}" in
      22.04|24.04) ;;
      *) warn "当前 Ubuntu 版本为 ${OS_VERSION_ID:-未知}，脚本主要验证于 Ubuntu 22.04/24.04。" ;;
    esac
  fi

  local missing_commands=()
  local cmd
  for cmd in apt apt-cache python3; do
    command_exists "${cmd}" || missing_commands+=("${cmd}")
  done
  if [ "${EUID}" -ne 0 ]; then
    command_exists sudo || missing_commands+=("sudo")
  fi
  if ((${#missing_commands[@]} > 0)); then
    die "缺少必要命令：${missing_commands[*]}"
  fi

  step_done "检查安装环境"
}

sudo_run() {
  if [ "${EUID}" -eq 0 ]; then
    "$@"
  elif [[ -n "${SUDO_PASSWORD}" ]]; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S -p '' "$@"
  else
    sudo "$@"
  fi
}

require_sudo() {
  if [ "${EUID}" -eq 0 ]; then
    return 0
  fi
  if [[ -n "${SUDO_PASSWORD}" ]]; then
    if ! printf '%s\n' "${SUDO_PASSWORD}" | sudo -S -p '' -v; then
      die "sudo 密码无效，请检查 SUDO_PASSWORD。"
    fi
  elif ! sudo -v; then
    die "无法获取 sudo 权限，请确认当前用户可使用 sudo。"
  fi
}

verify_packages_available() {
  info "检查 apt 仓库中的 fcitx5/rime 包"

  local missing_packages=()
  local package candidate
  for package in "${PACKAGES[@]}"; do
    candidate="$(apt-cache policy "${package}" | awk '/Candidate:/ {print $2; exit}')"
    if [[ -z "${candidate}" || "${candidate}" == "(none)" ]]; then
      missing_packages+=("${package}")
    fi
  done

  if ((${#missing_packages[@]} > 0)); then
    die "当前 apt 仓库中找不到这些包：${missing_packages[*]}"
  fi
}

install_packages() {
  step_start "安装 fcitx5 与依赖包"
  sudo_run apt update
  verify_packages_available
  sudo_run env DEBIAN_FRONTEND=noninteractive apt install -y "${PACKAGES[@]}"
  step_done "安装 fcitx5 与依赖包"
}

configure_im_framework() {
  step_start "设置默认输入法框架为 fcitx5"
  im-config -n fcitx5 || true
  step_done "设置默认输入法框架为 fcitx5"
}

# 写入输入法环境变量。
# 不再使用 ~/.pam_environment：PAM 1.5 起已移除对用户级 pam_environment 的支持
# （Ubuntu 24.04 上写入无效，22.04 默认也不读取）。改为：
#   - ~/.config/environment.d/95-fcitx5.conf：systemd 用户会话（GNOME Wayland 等）
#   - ~/.xprofile：X11 会话（display manager 登录时 source）
write_input_method_env() {
  step_start "写入输入法环境变量"

  mkdir -p "$(dirname "${ENVD_FILE}")"
  cat > "${ENVD_FILE}" <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
INPUT_METHOD=fcitx5
SDL_IM_MODULE=fcitx5
GLFW_IM_MODULE=fcitx5
EOF
  info "已写入 ${ENVD_FILE}"

  # ~/.xprofile 中维护带标记的配置块，重复执行时先清除旧块再追加
  touch "${XPROFILE_FILE}"
  sed -i '/^# >>> oh-my-linux fcitx5 >>>$/,/^# <<< oh-my-linux fcitx5 <<<$/d' "${XPROFILE_FILE}"
  cat >> "${XPROFILE_FILE}" <<'EOF'
# >>> oh-my-linux fcitx5 >>>
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export INPUT_METHOD=fcitx5
export SDL_IM_MODULE=fcitx5
export GLFW_IM_MODULE=fcitx5
# <<< oh-my-linux fcitx5 <<<
EOF
  info "已写入 ${XPROFILE_FILE}"

  if [[ -f "${HOME_DIR}/.pam_environment" ]]; then
    warn "检测到 ~/.pam_environment（旧版脚本写入，PAM 1.5+ 已不再读取），如无其他用途可自行删除。"
  fi

  step_done "写入输入法环境变量"
}

configure_autostart() {
  step_start "配置 fcitx5 开机自启动"
  mkdir -p "${AUTOSTART_DIR}"

  if [[ -f /etc/xdg/autostart/org.fcitx.Fcitx5.desktop ]]; then
    cp /etc/xdg/autostart/org.fcitx.Fcitx5.desktop "${AUTOSTART_FILE}"
  else
    cat > "${AUTOSTART_FILE}" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Fcitx 5
GenericName=Input Method
Comment=Start Input Method
Exec=fcitx5
Terminal=false
OnlyShowIn=KDE;GNOME;XFCE;LXQt;MATE;Unity;
X-GNOME-Autostart-enabled=true
NoDisplay=false
EOF
  fi

  python3 - <<'PY'
from pathlib import Path
path = Path.home() / ".config/autostart/org.fcitx.Fcitx5.desktop"
text = path.read_text()
lines = text.splitlines()
keys = {
    "X-GNOME-Autostart-enabled": "true",
    "Hidden": "false",
}
for key, value in keys.items():
    prefix = f"{key}="
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            lines[i] = f"{key}={value}"
            break
    else:
        lines.append(f"{key}={value}")
path.write_text("\n".join(lines) + "\n")
PY
  step_done "配置 fcitx5 开机自启动"
}

install_rime_ice() {
  step_start "安装 rime-ice ${OML_RIME_ICE_VERSION} 词库"
  mkdir -p "${RIME_DIR}"

  # 优先使用离线包内置的 zip，无则联网下载
  if [[ -f "${RIME_ZIP_LOCAL}" ]]; then
    info "使用本地 rime-ice 资源：${RIME_ZIP_LOCAL}"
    cp "${RIME_ZIP_LOCAL}" "${RIME_ZIP}"
  else
    info "本地未找到 rime-ice 资源，从网络下载：${OML_RIME_ICE_URL}"
    wget -O "${RIME_ZIP}" "${OML_RIME_ICE_URL}"
  fi

  unzip -q "${RIME_ZIP}" -d "${RIME_UNZIP_DIR}"

  local src_dir
  src_dir="${RIME_UNZIP_DIR}/rime-ice-${OML_RIME_ICE_VERSION}"
  [[ -d "${src_dir}" ]] || die "未找到解压后的 rime-ice 目录：${src_dir}"

  if compgen -G "${RIME_DIR}/*" > /dev/null; then
    local backup_dir
    backup_dir="${HOME_DIR}/rime-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"
    cp -a "${RIME_DIR}/." "${backup_dir}/"
    info "已备份现有 Rime 配置到：${backup_dir}"
  fi

  rm -rf "${RIME_DIR}"
  mkdir -p "${RIME_DIR}"
  cp -a "${src_dir}/." "${RIME_DIR}/"
  step_done "安装 rime-ice ${OML_RIME_ICE_VERSION} 词库"
}

install_candidate_theme() {
  step_start "安装 ${THEME_NAME} 候选框主题"

  local theme_zip="${ROOT_DIR}/resources/${THEME_NAME}.zip"
  if [[ ! -f "${theme_zip}" ]]; then
    warn "未找到主题资源 ${theme_zip}，跳过主题安装"
    return 0
  fi

  mkdir -p "${THEME_DIR}"
  rm -rf "${THEME_DIR:?}/${THEME_NAME}"
  unzip -q "${theme_zip}" -d "${THEME_DIR}"
  [[ -f "${THEME_DIR}/${THEME_NAME}/theme.conf" ]] || \
    die "主题解压结果异常：缺少 ${THEME_DIR}/${THEME_NAME}/theme.conf"

  # 在 classicui 配置中启用该主题
  local classicui_conf="${HOME_DIR}/.config/fcitx5/conf/classicui.conf"
  mkdir -p "$(dirname "${classicui_conf}")"
  if [[ -f "${classicui_conf}" ]] && grep -q '^Theme=' "${classicui_conf}"; then
    sed -i "s/^Theme=.*/Theme=${THEME_NAME}/" "${classicui_conf}"
  else
    echo "Theme=${THEME_NAME}" >> "${classicui_conf}"
  fi

  step_done "安装 ${THEME_NAME} 候选框主题"
}

ensure_rime_in_profile() {
  step_start "写入 fcitx5 profile，预置 Rime 输入法"
  mkdir -p "${HOME_DIR}/.config/fcitx5"
  cat > "${HOME_DIR}/.config/fcitx5/profile" <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=rime

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=rime
# Layout
Layout=

[GroupOrder]
0=Default
EOF
  step_done "写入 fcitx5 profile"
}

clear_rime_cache() {
  info "清理 Rime 编译缓存"
  rm -f "${RIME_DIR}"/*.bin
}

start_or_restart_fcitx5() {
  info "尝试启动 fcitx5"
  pkill -x fcitx5 2>/dev/null || true
  nohup fcitx5 >/tmp/fcitx5.log 2>&1 & disown || true
}

print_next_steps() {
  cat <<'EOF'

安装与配置已完成。

说明：
1. 已安装 fcitx5、fcitx5-rime 和相关前端。
2. 已写入 ~/.config/environment.d/95-fcitx5.conf 与 ~/.xprofile（输入法环境变量）。
3. 已配置 ~/.config/autostart/org.fcitx.Fcitx5.desktop 为开机自启动。
4. 已安装 rime-ice 词库与 Alpha-white 候选框主题。
5. 已预置 fcitx5 profile，包含键盘与 Rime。

你还需要做的事：
1. 注销并重新登录，使环境变量对整个桌面会话生效。
2. 登录后如未自动看到输入法托盘，手动运行一次 fcitx5。
3. 如托盘图标已出现，可右键 Fcitx5 图标选择"重新部署"。
4. 用 Ctrl+Space 切换输入法，测试 nihao / zhongwen。

如注销重登后仍有应用无法使用输入法，再考虑重启系统。
EOF
}

main() {
  parse_args "$@"

  if ! has_graphical_session && [ "${FORCE_INSTALL}" != "1" ]; then
    info "未检测到图形会话（服务器/容器/SSH 环境），跳过 fcitx5 + Rime 输入法安装。"
    info "如确需安装（例如通过 SSH 配置带桌面的机器），请使用 --force 参数。"
    exit 0
  fi

  if ! has_graphical_session; then
    warn "未检测到图形会话，--force 模式继续安装；安装后需登录图形桌面才能使用输入法。"
  fi

  check_environment
  require_sudo
  TMP_DIR="$(mktemp -d)"
  RIME_ZIP="${TMP_DIR}/rime-ice.zip"
  RIME_UNZIP_DIR="${TMP_DIR}/rime-ice-src"
  install_packages
  configure_im_framework
  write_input_method_env
  configure_autostart
  install_rime_ice
  install_candidate_theme
  ensure_rime_in_profile
  clear_rime_cache
  start_or_restart_fcitx5
  print_next_steps
}

main "$@"
