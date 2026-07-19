#!/usr/bin/env bash
#
# oh-my-linux · zsh + tmux 终端环境离线安装脚本
#
# 功能：离线安装 zsh、Oh My Zsh、Powerlevel10k 主题、zsh 插件、tmux、Oh My Tmux
# 支持：Debian 系发行版（Debian/Ubuntu 及其衍生版）
# 特点：支持重入（中断后重新运行可继续安装）
#
# 用法：
#   ./install_zsh_tmux.sh                # 交互安装
#   ./install_zsh_tmux.sh --unattended   # 无人值守安装（CI/容器/批量部署）

# 严格模式，但允许管道命令失败
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="$HOME/.oml_zsh_tmux_install_progress"
LOG_FILE="$HOME/.oml_zsh_tmux_install.log"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
用法: ./install_zsh_tmux.sh [选项]

选项:
  -y, --unattended   无人值守模式：所有确认采用默认值（覆盖旧安装、设默认 shell）
  -h, --help         显示本帮助
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--unattended)
        OML_UNATTENDED=1
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

# ======== 辅助函数 ========

# 检查本地材料是否齐全
check_materials() {
  local missing_materials=()
  local lib_dir="$SCRIPT_DIR/libraries"
  local res_dir="$SCRIPT_DIR/resources"

  [ -d "$lib_dir/oh-my-zsh" ] || missing_materials+=("Oh My Zsh 仓库")
  [ -d "$lib_dir/powerlevel10k" ] || missing_materials+=("Powerlevel10k 主题")
  [ -d "$lib_dir/zsh-autosuggestions" ] || missing_materials+=("zsh-autosuggestions 插件")
  [ -d "$lib_dir/zsh-syntax-highlighting" ] || missing_materials+=("zsh-syntax-highlighting 插件")
  [ -d "$lib_dir/oh-my-tmux" ] || missing_materials+=("Oh My Tmux 仓库")
  [ -f "$res_dir/MesloLGS NF Regular.ttf" ] || missing_materials+=("MesloLGS NF Regular.ttf 字体")

  if [ ${#missing_materials[@]} -gt 0 ]; then
    error "缺少以下安装材料:"
    for material in "${missing_materials[@]}"; do
      echo -e "${RED}- $material${RESET}"
    done
    error "若从 git 仓库直接运行，请先执行: git submodule update --init --recursive"
    return 1
  fi

  return 0
}

# 拷贝 library 到目标位置，并剥离 VCS 元数据。
# 子模块工作区中的 .git 是指向主仓库 .git/modules 的相对路径指针文件，
# 拷贝到 $HOME 后指针失效，且会干扰 omz update 等自更新逻辑，必须移除。
copy_library() {
  local src="$1"
  local dst="$2"
  cp -r "$src" "$dst"
  rm -rf "$dst/.git"
}

# 错误处理
handle_error() {
  error "在 ${BASH_SOURCE[1]} 的第 ${BASH_LINENO[0]} 行发生错误"
  warn "安装已中断，但可重新运行脚本继续。"
  exit 1
}

# 安装清理
cleanup() {
  if [ "$1" == "success" ]; then
    info "清理安装进度文件..."
    rm -f "$PROGRESS_FILE"
    success "安装完成！"
  else
    warn "安装未完成，保留进度文件以便下次继续。"
  fi
}

trap 'handle_error' ERR

# 初始化日志
init_logs() {
  touch "$PROGRESS_FILE"
  echo "# oh-my-linux zsh & tmux 安装日志 - $(date)" > "$LOG_FILE"
  info "安装日志位置: $LOG_FILE"
}

# ======== 安装步骤 ========

# 0. 初始化
init_installation() {
  if ! is_step_done "init"; then
    step_start "初始化安装环境"
    init_logs

    info "检查离线安装材料"
    if ! check_materials; then
      error "缺少必要的离线安装材料，请先准备好所有必要文件"
      exit 1
    fi

    require_debian_family

    mark_step_done "init"
    step_done "初始化安装环境"
  fi
}

# 1. 安装必要依赖
install_dependencies() {
  if ! is_step_done "install_dependencies"; then
    step_start "安装必要的依赖"
    mark_step_in_progress "install_dependencies"

    local deps=(zsh tmux git fontconfig)
    local missing_deps=()

    for dep in "${deps[@]}"; do
      if ! command_exists "$dep"; then
        missing_deps+=("$dep")
      fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
      info "安装缺失的依赖: ${missing_deps[*]}"
      $SUDO apt update || {
        warn "apt update 失败，但将继续尝试安装"
      }
      $SUDO env DEBIAN_FRONTEND=noninteractive apt install -y "${missing_deps[@]}" || {
        error "依赖安装失败，请手动安装 zsh、tmux、git 和 fontconfig"
        return 1
      }
    else
      info "所有依赖已安装"
    fi

    mark_step_done "install_dependencies"
    step_done "依赖安装"
  fi
}

# 2. 安装 Oh My Zsh
install_oh_my_zsh() {
  if ! is_step_done "install_oh_my_zsh"; then
    step_start "安装 Oh My Zsh"
    mark_step_in_progress "install_oh_my_zsh"

    ZSH_DIR="$HOME/.oh-my-zsh"

    if [ -d "$ZSH_DIR" ]; then
      warn "发现现有的 Oh My Zsh 安装"
      if confirm "是否备份并覆盖现有的 Oh My Zsh？" "y"; then
        info "备份并移除现有的 Oh My Zsh"
        mv "$ZSH_DIR" "$ZSH_DIR.bak_$(date +%Y%m%d_%H%M%S)"
      else
        warn "保留现有的 Oh My Zsh 安装"
        mark_step_done "install_oh_my_zsh"
        step_done "Oh My Zsh 安装"
        return 0
      fi
    fi

    info "从本地材料安装 Oh My Zsh"
    copy_library "$SCRIPT_DIR/libraries/oh-my-zsh" "$ZSH_DIR"

    # 备份原有 .zshrc
    if [ -f "$HOME/.zshrc" ]; then
      mv "$HOME/.zshrc" "$HOME/.zshrc.bak_$(date +%Y%m%d_%H%M%S)"
      info "已备份原有的 .zshrc 文件"
    fi

    # 生成 .zshrc（优先使用离线包内的安装脚本；其次使用子模块内脚本；最后回退到模板）
    local omz_install_script=""
    if [ -f "$SCRIPT_DIR/resources/omz_install.sh" ]; then
      omz_install_script="$SCRIPT_DIR/resources/omz_install.sh"
    elif [ -f "$SCRIPT_DIR/libraries/oh-my-zsh/tools/install.sh" ]; then
      omz_install_script="$SCRIPT_DIR/libraries/oh-my-zsh/tools/install.sh"
    fi

    if [ -n "$omz_install_script" ]; then
      info "使用脚本生成 .zshrc: $omz_install_script"
      RUNZSH=no KEEP_ZSHRC=no ZSH="$ZSH_DIR" sh "$omz_install_script" --unattended || {
        warn "安装脚本执行失败，使用模板生成 .zshrc"
        cp "$ZSH_DIR/templates/zshrc.zsh-template" "$HOME/.zshrc"
        sed -i "s|^export ZSH=.*|export ZSH=\"$ZSH_DIR\"|" "$HOME/.zshrc"
      }
    else
      info "未找到 Oh My Zsh 安装脚本，使用模板生成 .zshrc"
      cp "$ZSH_DIR/templates/zshrc.zsh-template" "$HOME/.zshrc"
      sed -i "s|^export ZSH=.*|export ZSH=\"$ZSH_DIR\"|" "$HOME/.zshrc"
    fi
    mark_step_done "install_oh_my_zsh"
    step_done "Oh My Zsh 安装"
  fi
}

# 3. 设置 ZSH_CUSTOM 变量
set_zsh_custom() {
  if ! is_step_done "set_zsh_custom"; then
    step_start "设置 ZSH_CUSTOM 变量"
    mark_step_in_progress "set_zsh_custom"

    if grep -q "^# ZSH_CUSTOM=" "$HOME/.zshrc"; then
      sed -i 's|^# ZSH_CUSTOM=.*|ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"|' "$HOME/.zshrc"
    elif grep -q "^ZSH_CUSTOM=" "$HOME/.zshrc"; then
      sed -i 's|^ZSH_CUSTOM=.*|ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"|' "$HOME/.zshrc"
    else
      echo 'ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"' >> "$HOME/.zshrc"
    fi

    mark_step_done "set_zsh_custom"
    step_done "ZSH_CUSTOM 变量设置"
  fi
}

# 4. 安装 Powerlevel10k 主题
install_powerlevel10k() {
  if ! is_step_done "install_powerlevel10k"; then
    step_start "安装 Powerlevel10k 主题"
    mark_step_in_progress "install_powerlevel10k"

    ZSH_CUSTOM_DIR="$HOME/.oh-my-zsh/custom"
    THEME_DIR="$ZSH_CUSTOM_DIR/themes/powerlevel10k"

    mkdir -p "$ZSH_CUSTOM_DIR/themes"

    if [ -d "$THEME_DIR" ]; then
      info "移除现有的 Powerlevel10k 主题"
      rm -rf "$THEME_DIR"
    fi

    info "从本地材料安装 Powerlevel10k 主题"
    copy_library "$SCRIPT_DIR/libraries/powerlevel10k" "$THEME_DIR"

    # 设置主题
    info "配置 Powerlevel10k 为默认主题"
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

    # 复制 p10k 配置文件（如果存在）
    if [ -f "$SCRIPT_DIR/.p10k.zsh" ]; then
      info "使用本地 p10k 配置文件"
      cp "$SCRIPT_DIR/.p10k.zsh" "$HOME/.p10k.zsh"
    else
      info "添加 p10k 自动配置提示到 .zshrc"
      if ! grep -q "# To customize prompt, run \`p10k configure\`" "$HOME/.zshrc"; then
        echo '# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.' >> "$HOME/.zshrc"
        echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> "$HOME/.zshrc"
      fi
    fi

    mark_step_done "install_powerlevel10k"
    step_done "Powerlevel10k 主题安装"
  fi
}

# 5. 安装 zsh 插件
install_zsh_plugins() {
  if ! is_step_done "install_zsh_plugins"; then
    step_start "安装 zsh 插件"
    mark_step_in_progress "install_zsh_plugins"

    ZSH_CUSTOM_DIR="$HOME/.oh-my-zsh/custom"
    mkdir -p "$ZSH_CUSTOM_DIR/plugins"

    # 安装 zsh-autosuggestions
    AUTOSUG_DIR="$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
    if [ -d "$AUTOSUG_DIR" ]; then
      info "移除现有的 zsh-autosuggestions 插件"
      rm -rf "$AUTOSUG_DIR"
    fi
    info "从本地材料安装 zsh-autosuggestions 插件"
    copy_library "$SCRIPT_DIR/libraries/zsh-autosuggestions" "$AUTOSUG_DIR"

    # 安装 zsh-syntax-highlighting
    SYNTAX_DIR="$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
    if [ -d "$SYNTAX_DIR" ]; then
      info "移除现有的 zsh-syntax-highlighting 插件"
      rm -rf "$SYNTAX_DIR"
    fi
    info "从本地材料安装 zsh-syntax-highlighting 插件"
    copy_library "$SCRIPT_DIR/libraries/zsh-syntax-highlighting" "$SYNTAX_DIR"

    # 更新 .zshrc 的插件配置
    info "配置 zsh 插件"
    if grep -q "^plugins=.*" "$HOME/.zshrc"; then
      sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
    else
      echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$HOME/.zshrc"
    fi

    mark_step_done "install_zsh_plugins"
    step_done "zsh 插件安装"
  fi
}

# 6. 安装 MesloLGS NF 字体
install_nerd_fonts() {
  if ! is_step_done "install_nerd_fonts"; then
    step_start "安装 MesloLGS NF 字体"
    mark_step_in_progress "install_nerd_fonts"

    FONT_NAME="MesloLGS NF"
    FONT_FILE="MesloLGS NF Regular.ttf"
    FONT_DIR="$HOME/.local/share/fonts"

    if fc-list | grep -qi "$FONT_NAME"; then
      info "$FONT_NAME 字体已安装"
    else
      info "安装 $FONT_NAME 字体"
      mkdir -p "$FONT_DIR"

      cp "$SCRIPT_DIR/resources/$FONT_FILE" "$FONT_DIR/" || {
        error "无法复制字体文件"
        return 1
      }

      info "更新字体缓存"
      fc-cache -f || warn "字体缓存更新失败，可能需要手动配置终端字体"
    fi

    mark_step_done "install_nerd_fonts"
    step_done "MesloLGS NF 字体安装"
  fi
}

# 7. 安装 Oh My Tmux
install_oh_my_tmux() {
  if ! is_step_done "install_oh_my_tmux"; then
    step_start "安装 Oh My Tmux"
    mark_step_in_progress "install_oh_my_tmux"

    TMUX_DIR="$HOME/.tmux"

    if [ -d "$TMUX_DIR" ]; then
      info "移除现有的 Oh My Tmux 配置"
      rm -rf "$TMUX_DIR"
    fi

    info "从本地材料安装 Oh My Tmux"
    copy_library "$SCRIPT_DIR/libraries/oh-my-tmux" "$TMUX_DIR"

    # 创建配置链接
    info "创建 tmux 配置链接"
    if [ -f "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
      mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak_$(date +%Y%m%d_%H%M%S)"
      info "已备份原有的 .tmux.conf 文件"
    fi

    ln -sf "$TMUX_DIR/.tmux.conf" "$HOME/.tmux.conf"

    # 复制本地配置
    if [ -f "$HOME/.tmux.conf.local" ]; then
      mv "$HOME/.tmux.conf.local" "$HOME/.tmux.conf.local.bak_$(date +%Y%m%d_%H%M%S)"
      info "已备份原有的 .tmux.conf.local 文件"
    fi

    # 优先使用自定义配置，否则使用默认配置
    if [ -f "$SCRIPT_DIR/.tmux.conf.local" ]; then
      info "使用自定义 .tmux.conf.local 配置"
      cp "$SCRIPT_DIR/.tmux.conf.local" "$HOME/.tmux.conf.local"
    else
      info "使用默认 .tmux.conf.local 配置"
      cp "$TMUX_DIR/.tmux.conf.local" "$HOME/.tmux.conf.local"
    fi

    mark_step_done "install_oh_my_tmux"
    step_done "Oh My Tmux 安装"
  fi
}

# 8. 设置默认 shell 为 zsh
set_default_shell() {
  if ! is_step_done "set_default_shell"; then
    step_start "设置 zsh 为默认 shell"
    mark_step_in_progress "set_default_shell"

    local zsh_path current_user
    zsh_path="$(command -v zsh)"
    current_user="${USER:-$(id -un)}"

    if [ "$SHELL" = "$zsh_path" ]; then
      info "zsh 已经是默认 shell"
    elif ! command_exists chsh; then
      warn "未找到 chsh 命令，无法更改默认 shell"
      echo "要手动将 zsh 设为默认 shell，请执行: chsh -s $zsh_path"
    elif confirm "是否将默认 shell 更改为 zsh？" "y"; then
      info "将默认 shell 更改为 zsh"
      if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        chsh -s "$zsh_path" "$current_user" || {
          warn "无法将 zsh 设为默认，请手动执行: chsh -s $zsh_path"
        }
      elif command_exists sudo && sudo -n true 2>/dev/null; then
        sudo chsh -s "$zsh_path" "$current_user" || {
          warn "无法将 zsh 设为默认，请手动执行: chsh -s $zsh_path"
        }
      elif [ "${OML_UNATTENDED:-0}" = "1" ]; then
        # 无人值守下 chsh 需要密码输入，会阻塞，只提示不执行
        warn "无人值守模式下无免密 sudo，跳过更改默认 shell"
        echo "请手动执行: chsh -s $zsh_path"
      else
        chsh -s "$zsh_path" || {
          warn "无法将 zsh 设为默认，请手动执行: chsh -s $zsh_path"
        }
      fi
    else
      info "跳过更改默认 shell"
    fi

    mark_step_done "set_default_shell"
    step_done "默认 shell 设置"
  fi
}

# ======== 主函数 ========
main() {
  parse_args "$@"

  echo -e "${CYAN}=====================================================${RESET}"
  echo -e "${CYAN}      oh-my-linux · zsh & tmux 离线安装              ${RESET}"
  echo -e "${CYAN}=====================================================${RESET}"
  echo ""

  # 检查是否存在运行中的安装
  if grep -q "=in_progress$" "$PROGRESS_FILE" 2>/dev/null; then
    warn "检测到上次中断的安装，继续执行..."
  fi

  # 执行安装步骤
  init_installation
  install_dependencies
  install_oh_my_zsh
  set_zsh_custom
  install_powerlevel10k
  install_zsh_plugins
  install_nerd_fonts
  install_oh_my_tmux
  set_default_shell

  # 安装完成
  cleanup "success"

  echo -e "\n${GREEN}=====================================================${RESET}"
  echo -e "${GREEN}      zsh & tmux 安装已完成！                        ${RESET}"
  echo -e "${GREEN}=====================================================${RESET}"
  echo -e "\n${YELLOW}请注意以下事项:${RESET}"
  echo -e "1. ${BLUE}请注销并重新登录以应用更改${RESET}"
  echo -e "2. ${BLUE}将终端字体更改为 ${MAGENTA}MesloLGS NF${BLUE}，以支持所有图标${RESET}"
  echo -e "3. ${BLUE}首次登录时可运行 ${MAGENTA}p10k configure${BLUE} 配置 Powerlevel10k 主题${RESET}"
  echo -e "4. ${BLUE}tmux 使用前缀键 ${MAGENTA}Ctrl+a${BLUE} 或 ${MAGENTA}Ctrl+b${BLUE} 激活命令${RESET}"
  echo -e "5. ${BLUE}常用 tmux 命令: ${MAGENTA}Ctrl+a c${BLUE}(新建窗口)、${MAGENTA}Ctrl+a 数字键${BLUE}(切换窗口)${RESET}"
  echo -e "6. ${BLUE}tmux 分屏: ${MAGENTA}Ctrl+a %${BLUE}(垂直分屏)、${MAGENTA}Ctrl+a \"${BLUE}(水平分屏)${RESET}"
  echo -e "\n${GREEN}安装日志保存在: ${MAGENTA}$LOG_FILE${RESET}\n"

  if confirm "是否要立即启动 zsh 体验新配置？" "n"; then
    exec zsh -l
  else
    echo -e "${BLUE}您可以稍后运行 ${MAGENTA}zsh${BLUE} 命令来启动新的 shell${RESET}"
  fi
}

main "$@"
