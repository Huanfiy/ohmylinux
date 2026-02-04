#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PKG_BASENAME="newpc_u22"
OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

usage() {
  cat <<'EOF'
Usage:
  ./run.sh update
  ./run.sh create

Commands:
  update   更新子模块仓库（会拉取远端最新提交，并更新本地子模块指针）
  create   生成离线包：dist/newpc_u22_YYYYMMDD.tar.gz
EOF
}

do_update() {
  need_cmd git

  cd "$SCRIPT_DIR"
  [ -f ".gitmodules" ] || die "未找到 .gitmodules，请先在该目录初始化子模块"

  git submodule sync --recursive
  git submodule update --init --recursive

  echo "正在拉取子模块远端更新..."
  git submodule update --remote --merge --recursive

  echo ""
  echo "update 完成。若子模块指针有变化，请在主仓库中自行提交更新。"
}

fetch_omz_install_script() {
  local out_path="$1"

  if command -v curl >/dev/null 2>&1; then
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
  cp -a "$SCRIPT_DIR/install_offline.sh" "$SCRIPT_DIR/run.sh" "$SCRIPT_DIR/README.md" "$staging_dir/"
  cp -a "$SCRIPT_DIR/resources" "$staging_dir/"
  cp -a "$SCRIPT_DIR/libraries" "$staging_dir/"

  # 离线包内不需要 VCS 元数据
  find "$staging_dir/libraries" -type d -name .git -prune -exec rm -rf '{}' +

  # create 时临时拉取最新版 OMZ install.sh（无网络则回退到子模块内脚本）
  fetch_omz_install_script "$staging_dir/resources/omz_install.sh"

  chmod +x "$staging_dir/install_offline.sh" "$staging_dir/run.sh" "$staging_dir/resources/omz_install.sh" || true

  # 打包（tar 内包含顶层目录）
  tar -C "$staging_parent" -czf "$out_tgz" "$pkg_dir_name"

  echo ""
  echo "离线包已生成：$out_tgz"
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

