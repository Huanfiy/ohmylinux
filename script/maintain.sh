#!/usr/bin/env bash
#
# oh-my-linux 维护脚本：更新子模块 / 生成离线安装包

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=script/common.sh
source "$ROOT_DIR/script/common.sh"

PKG_BASENAME="oh-my-linux"

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

  cd "$ROOT_DIR"
  [ -e .git ] && [ -f .gitmodules ] || die "update 仅适用于 Git 仓库，不适用于离线包"

  git submodule sync --recursive
  git submodule update --init --recursive

  info "正在拉取子模块远端更新..."
  git submodule update --remote --merge --recursive

  echo ""
  info "update 完成。若子模块指针有变化，请在主仓库中自行提交更新。"
}

# 下载 rime-ice 词库 zip 到离线包资源目录（已存在则复用，失败仅告警：
# 离线包仍可用于 zsh/tmux，fcitx5 脚本会在安装时回退为联网下载）
fetch_rime_ice_zip() {
  local out_path="$1"
  local cached="$ROOT_DIR/resources/rime-ice-${OML_RIME_ICE_VERSION}.zip"

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

  cd "$ROOT_DIR"
  [ -e .git ] && [ -f .gitmodules ] || die "create 请在 Git 仓库中执行；离线包可直接用于 install"

  # 确保子模块存在（已初始化时无需网络，否则可能需要联网拉取）
  git submodule update --init --recursive

  local date_suffix
  date_suffix="$(date +%Y%m%d)"
  local pkg_dir_name="${PKG_BASENAME}_${date_suffix}"

  local dist_dir="$ROOT_DIR/dist"
  local staging_parent="$ROOT_DIR/.staging"
  local staging_dir="$staging_parent/$pkg_dir_name"
  local out_tgz="$dist_dir/${pkg_dir_name}.tar.gz"

  rm -rf "$staging_dir"
  mkdir -p "$staging_dir" "$dist_dir"

  # 拷贝必要文件/目录
  cp -a "$ROOT_DIR/run.sh" "$ROOT_DIR/README.md" "$ROOT_DIR/LICENSE" \
    "$ROOT_DIR/script" "$ROOT_DIR/resources" "$ROOT_DIR/libraries" "$staging_dir/"

  # 一并携带可选的个人终端配置，与直接从仓库安装保持一致。
  local config
  for config in .p10k.zsh .tmux.conf.local; do
    if [ -f "$ROOT_DIR/$config" ]; then
      cp -a "$ROOT_DIR/$config" "$staging_dir/"
    fi
  done

  # 离线包内不需要 VCS 元数据
  find "$staging_dir/libraries" -name .git -prune -exec rm -rf '{}' +

  # 预下载 rime-ice 词库；apt 依赖仍需预装或使用可访问的 apt 源
  fetch_rime_ice_zip "$staging_dir/resources/rime-ice-${OML_RIME_ICE_VERSION}.zip"

  chmod +x "$staging_dir/run.sh" "$staging_dir"/script/*.sh

  # 打包（tar 内包含顶层目录）
  tar -C "$staging_parent" -czf "$out_tgz" "$pkg_dir_name"

  echo ""
  success "离线包已生成：$out_tgz"
}

main() {
  local cmd="${1:-}"
  [ "$#" -le 1 ] || die "$cmd 不接受额外参数（使用 ./run.sh --help 查看帮助）"
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
