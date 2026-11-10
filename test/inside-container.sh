#!/usr/bin/env bash
#
# oh-my-linux 容器内测试脚本（由 test/docker-test.sh 调用，以 root 身份运行）
#
# 流程：
#   1. 准备环境：安装 sudo，创建带免密 sudo 的普通用户 tester（模拟真机场景）
#   2. 以 tester 身份执行 run.sh install terminal --unattended
#   3. 逐项断言安装结果
#   4. 验证 run.sh install im 在无图形会话下正确跳过
#   5. 验证 run.sh install terminal 可重复执行（重入）
#   6. （可选 OML_TEST_FCITX5=1）执行 fcitx5 --force 完整安装并断言

set -euo pipefail

REPO="/opt/oh-my-linux"
TEST_USER="tester"
export DEBIAN_FRONTEND=noninteractive

PASS_COUNT=0
FAIL_COUNT=0

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  [ok] $desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  [FAIL] $desc"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

as_tester() {
  su - "$TEST_USER" -c "$*"
}

echo "==> [1/6] 准备容器环境"
apt-get update -qq
apt-get install -y -qq sudo >/dev/null
if [ "${OML_TEST_FCITX5:-0}" = "1" ]; then
  # fcitx5 脚本的环境检查依赖 python3（真机桌面环境默认自带）
  apt-get install -y -qq python3 >/dev/null
fi
useradd -m -s /bin/bash "$TEST_USER"
echo "$TEST_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$TEST_USER"

echo "==> [2/6] 以 $TEST_USER 身份执行 run.sh install terminal --unattended"
as_tester "bash $REPO/run.sh install terminal --unattended"

echo "==> [3/6] 断言 zsh/tmux 安装结果"
TESTER_HOME="/home/$TEST_USER"

check "zsh 已安装" as_tester "command -v zsh"
check "tmux 已安装" as_tester "command -v tmux"
check "git 已安装" as_tester "command -v git"
check "HOME 下 .oh-my-zsh 存在" test -d "$TESTER_HOME/.oh-my-zsh"
check "HOME 下 .oh-my-zsh 无残留 .git 指针" test ! -e "$TESTER_HOME/.oh-my-zsh/.git"
check "p10k 主题已安装" test -d "$TESTER_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
check "p10k 主题无残留 .git 指针" test ! -e "$TESTER_HOME/.oh-my-zsh/custom/themes/powerlevel10k/.git"
check "zsh-autosuggestions 已安装" test -d "$TESTER_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
check "zsh-syntax-highlighting 已安装" test -d "$TESTER_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
check ".zshrc 配置了 p10k 主题" grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$TESTER_HOME/.zshrc"
check ".zshrc 配置了插件列表" grep -q 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$TESTER_HOME/.zshrc"
check "HOME 下 .tmux.conf 为符号链接" test -L "$TESTER_HOME/.tmux.conf"
check "HOME 下 .tmux.conf.local 存在" test -f "$TESTER_HOME/.tmux.conf.local"
check "HOME 下 .tmux 无残留 .git 指针" test ! -e "$TESTER_HOME/.tmux/.git"
check "MesloLGS NF 字体已注册" as_tester "fc-list | grep -qi 'MesloLGS NF'"
check "默认 shell 已切换为 zsh" bash -c "getent passwd $TEST_USER | grep -q '/zsh$'"
check "进度文件已清理" test ! -f "$TESTER_HOME/.oml_zsh_tmux_install_progress"
check "zsh 交互加载 .zshrc 正常" as_tester "TERM=xterm-256color POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true zsh -ic 'echo ZSH_RC_OK' | grep -q ZSH_RC_OK"
check "tmux 配置可加载" as_tester "tmux new-session -d -s smoke && tmux kill-session -t smoke"

echo "==> [4/6] 断言 fcitx5 脚本在无图形会话下跳过"
FCITX5_LOG="/tmp/fcitx5_skip.log"
FCITX5_RC=0
as_tester "bash $REPO/run.sh install im --unattended" >"$FCITX5_LOG" 2>&1 || FCITX5_RC=$?
if [ "$FCITX5_RC" -ne 0 ]; then
  cat "$FCITX5_LOG"
fi
check "无图形会话时以退出码 0 跳过" test "$FCITX5_RC" -eq 0
check "输出包含跳过提示" grep -q "跳过 fcitx5" "$FCITX5_LOG"
check "fcitx5 未被安装" bash -c '! command -v fcitx5'

echo "==> [5/6] 断言 run.sh install terminal 可重复执行"
as_tester "bash $REPO/run.sh install terminal --unattended"
check "重复执行后 ~/.oh-my-zsh 仍存在" test -d "$TESTER_HOME/.oh-my-zsh"
check "重复执行生成了备份目录" bash -c "ls -d $TESTER_HOME/.oh-my-zsh.bak_* >/dev/null"

if [ "${OML_TEST_FCITX5:-0}" = "1" ]; then
  echo "==> [6/6] fcitx5 --force 完整安装测试"
  as_tester "bash $REPO/run.sh install im --unattended --force"
  check "fcitx5 已安装" as_tester "command -v fcitx5"
  check "rime-ice 词库已就位" test -f "$TESTER_HOME/.local/share/fcitx5/rime/default.yaml"
  check "Alpha-white 主题已安装" test -f "$TESTER_HOME/.local/share/fcitx5/themes/Alpha-white/theme.conf"
  check "classicui 已启用 Alpha-white 主题" grep -q '^Theme=Alpha-white' "$TESTER_HOME/.config/fcitx5/conf/classicui.conf"
  check "environment.d 输入法环境变量已写入" grep -q 'GTK_IM_MODULE=fcitx' "$TESTER_HOME/.config/environment.d/95-fcitx5.conf"
  check ".xprofile 输入法配置块已写入" grep -q 'oh-my-linux fcitx5' "$TESTER_HOME/.xprofile"
  check "fcitx5 profile 已预置 rime" grep -q 'Name=rime' "$TESTER_HOME/.config/fcitx5/profile"
  check "autostart 桌面项已配置" test -f "$TESTER_HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
else
  echo "==> [6/6] 跳过 fcitx5 完整安装测试（使用 --full 开启）"
fi

echo ""
echo "==> 断言通过 $PASS_COUNT 项，失败 $FAIL_COUNT 项"
[ "$FAIL_COUNT" -eq 0 ]
