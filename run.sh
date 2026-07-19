#!/usr/bin/env bash
#
# oh-my-linux 维护脚本：更新子模块 / 生成离线安装包

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PKG_BASENAME="oh-my-linux"
OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

need_cmd() {
  command_exists "$1" || die "缺少命令：$1"
}

usage() {
  cat <<'EOF'
用法:
  ./run.sh update
  ./run.sh create

命令:
  update   更新子模块仓库（会拉取远端最新提交，并更新本地子模块指针）
  create   生成离线包：dist/oh-my-linux_YYYYMMDD.tar.gz
EOF
}

do_update() {
  need_cmd git

  cd "$SCRIPT_DIR"
  [ -f ".gitmodules" ] || die "未找到 .gitmodules，请先在该目录初始化子模块"

  git submodule sync --recursive
  git submodule update --init --recursive

  info "正在拉取子模块远端更新..."
  git submodule update --remote --merge --recursive

  echo ""
  info "update 完成。若子模块指针有变化，请在主仓库中自行提交更新。"
}

fetch_omz_install_script() {
  local out_path="$1"

  if command_exists curl; then
    if curl -fsSL "$OMZ_INSTALL_URL" -o "$out_path"; then
      return 0
    fi
    warn "curl 下载失败，将使用本地 oh-my-zsh 子模块内的 install.sh 作为回退"
  else
    warn "未找到 curl，将使用本地 oh-my-zsh 子模块内的 install.sh 作为回退"
  fi

  local fallback="$SCRIPT_DIR/libraries/oh-my-zsh/tools/install.sh"
  [ -f "$fallback" ] || die "回退脚本不存在：$fallback"
  cp -a "$fallback" "$out_path"
}

# 下载 rime-ice 词库 zip 到离线包资源目录（已存在则复用，失败仅告警：
# 离线包仍可用于 zsh/tmux，fcitx5 脚本会在安装时回退为联网下载）
fetch_rime_ice_zip() {
  local out_path="$1"
  local cached="$SCRIPT_DIR/resources/rime-ice-${OML_RIME_ICE_VERSION}.zip"

  if [ -f "$cached" ]; then
    info "复用已缓存的 rime-ice 资源：$cached"
    cp -a "$cached" "$out_path"
    return 0
  fi

  if command_exists curl; then
    info "下载 rime-ice ${OML_RIME_ICE_VERSION}..."
    if curl -fsSL "$OML_RIME_ICE_URL" -o "$out_path"; then
      cp -a "$out_path" "$cached"
      return 0
    fi
  fi

  warn "rime-ice 下载失败或缺少 curl，离线包将不含 rime-ice（fcitx5 安装时需联网下载）"
  rm -f "$out_path"
}

do_create() {
  need_cmd tar
  need_cmd git
  need_cmd find

  cd "$SCRIPT_DIR"

  # 确保子模块存在（create 不强依赖网络）
  git submodule update --init --recursive

  local date_suffix
  date_suffix="$(date +%Y%m%d)"
  local pkg_dir_name="${PKG_BASENAME}_${date_suffix}"

  local dist_dir="$SCRIPT_DIR/dist"
  local staging_parent="$SCRIPT_DIR/.staging"
  local staging_dir="$staging_parent/$pkg_dir_name"
  local out_tgz="$dist_dir/${pkg_dir_name}.tar.gz"

  rm -rf "$staging_dir"
  mkdir -p "$staging_dir" "$dist_dir"

  # 拷贝必要文件/目录
  cp -a "$SCRIPT_DIR/install_zsh_tmux.sh" "$SCRIPT_DIR/install_fcitx5_rime.sh" \
    "$SCRIPT_DIR/run.sh" "$SCRIPT_DIR/README.md" "$staging_dir/"
  cp -a "$SCRIPT_DIR/lib" "$staging_dir/"
  cp -a "$SCRIPT_DIR/resources" "$staging_dir/"
  cp -a "$SCRIPT_DIR/libraries" "$staging_dir/"

  # 离线包内不需要 VCS 元数据
  find "$staging_dir/libraries" -name .git -prune -exec rm -rf '{}' +

  # create 时临时拉取最新版 OMZ install.sh（无网络则回退到子模块内脚本）
  fetch_omz_install_script "$staging_dir/resources/omz_install.sh"

  # 预下载 rime-ice 词库，使 fcitx5 安装脚本可完全离线执行
  fetch_rime_ice_zip "$staging_dir/resources/rime-ice-${OML_RIME_ICE_VERSION}.zip"

  chmod +x "$staging_dir/install_zsh_tmux.sh" "$staging_dir/install_fcitx5_rime.sh" \
    "$staging_dir/run.sh" "$staging_dir/resources/omz_install.sh" || true

  # 打包（tar 内包含顶层目录）
  tar -C "$staging_parent" -czf "$out_tgz" "$pkg_dir_name"

  echo ""
  success "离线包已生成：$out_tgz"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    update)
      shift
      do_update "$@"
      ;;
    create)
      shift
      do_create "$@"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      die "未知命令：$cmd（使用 -h 查看帮助）"
      ;;
  esac
}

main "$@"
