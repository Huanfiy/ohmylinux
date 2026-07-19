[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# oh-my-linux — Debian 系新机基础环境一键配置

面向虚拟机与新装 Linux 机器的基础工具配置包：克隆仓库或解压离线包后执行一条命令，得到配置完毕的 **Zsh + Oh My Zsh + Powerlevel10k + 常用插件 + Tmux + Oh My Tmux** 终端环境；图形桌面机器可另行执行输入法脚本，得到 **fcitx5 + Rime + rime-ice 词库** 中文输入环境。

## 支持范围

- **覆盖**：Debian 系发行版（Debian / Ubuntu 及其衍生版），主要验证于 Ubuntu 22.04、Ubuntu 24.04、Debian 12。
- **不覆盖**：RHEL / Fedora / Arch 等非 apt 包管理体系；macOS / WSL 未经验证。
- 输入法脚本仅适用于图形桌面环境；无图形会话（服务器、容器、SSH）时自动跳过，不产生任何变更。

## 📦 包含组件

以 Git submodules 方式管理以下 5 个仓库（避免在主仓库中直接跟踪其文件内容）：

1. **[Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)**：Zsh 配置框架
2. **[Powerlevel10k](https://github.com/romkatv/powerlevel10k)**：Zsh 主题
3. **[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)**：命令自动建议
4. **[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)**：命令语法高亮
5. **[Oh My Tmux!](https://github.com/gpakosz/.tmux)**：Tmux 配置

资源文件：

- `resources/MesloLGS NF Regular.ttf`：Powerlevel10k 推荐字体（Nerd Font）
- `resources/Alpha-white.zip`：fcitx5 候选框主题
- `resources/rime-ice-2024.05.21.zip`：rime-ice 词库（执行 `./run.sh create` 打包时自动下载缓存，仓库中不跟踪）

## 📁 目录结构

```text
.
├── install_zsh_tmux.sh        # zsh + tmux 终端环境安装（离线）
├── install_fcitx5_rime.sh     # fcitx5 + Rime 输入法安装（仅图形桌面）
├── run.sh                     # 维护脚本（update / create）
├── lib/
│   └── common.sh              # 公共函数库（日志、步骤进度、系统检查）
├── libraries/                 # 5 个仓库（git submodules）
├── resources/                 # 字体、主题、词库资源
└── test/
    ├── docker-test.sh         # Docker 多发行版测试矩阵（宿主机入口）
    ├── inside-container.sh    # 容器内安装与断言逻辑
    └── lint.sh                # shellcheck 静态检查（容器内执行）
```

## 🚀 使用方式

### 方式一：从 git 仓库安装

```bash
git clone --recurse-submodules <本仓库地址> && cd ohmylinux
./install_zsh_tmux.sh                # 终端环境（交互模式）
./install_zsh_tmux.sh --unattended   # 终端环境（无人值守，适合批量部署）
./install_fcitx5_rime.sh             # 输入法（仅图形桌面机器需要）
```

已克隆但缺少子模块时，先执行 `git submodule update --init --recursive`。

### 方式二：离线包安装（目标机器无网络）

1. 在有网络的机器上执行 `./run.sh create`，得到 `dist/oh-my-linux_YYYYMMDD.tar.gz`
2. 拷贝至目标机器解压，进入目录执行上述安装命令

离线包已内置 rime-ice 词库与 Oh My Zsh 安装脚本，安装过程不需要网络；唯一例外是 apt 依赖（`zsh`、`tmux`、`git`、`fontconfig`、fcitx5 相关包），完全断网的机器需预装依赖或配置离线 apt 源。

### 脚本行为说明

`install_zsh_tmux.sh`：

- 支持重入：中断后重新运行，从上次进度继续（进度记录于 `~/.oml_zsh_tmux_install_progress`）。
- 覆盖安装前自动备份：`~/.zshrc`、`~/.oh-my-zsh`、`~/.tmux.conf` 均备份为 `*.bak_时间戳`。
- `--unattended` 模式下所有确认自动采用默认值：覆盖旧安装（含备份）、设置 zsh 为默认 shell、不立即启动 zsh。

`install_fcitx5_rime.sh`：

- 通过 `XDG_CURRENT_DESKTOP` / `DISPLAY` 等变量检测图形会话，检测失败时直接退出且不做任何变更；SSH 配置带桌面的机器时使用 `--force` 跳过检测。
- 输入法环境变量写入 `~/.config/environment.d/95-fcitx5.conf`（systemd 用户会话）与 `~/.xprofile`（X11 会话）。不再使用 `~/.pam_environment`——PAM 1.5 起已移除该机制，Ubuntu 24.04 上写入无效。
- 支持 `SUDO_PASSWORD` 环境变量免交互提供 sudo 密码。

## 🧪 测试

全部测试在 Docker 容器内执行，不改动宿主机环境；宿主机仅需安装 Docker（验证于 Docker 29.6.0）。

```bash
./test/lint.sh                        # shellcheck 静态检查
./test/docker-test.sh                 # 默认矩阵：ubuntu:22.04 / ubuntu:24.04 / debian:12
./test/docker-test.sh ubuntu:24.04    # 仅测试单个镜像
./test/docker-test.sh --full          # 追加 fcitx5 --force 完整安装断言（容器内需联网）
```

测试内容：容器内创建普通用户 → 无人值守安装 → 逐项断言（组件落位、`.zshrc` 配置、字体注册、默认 shell、zsh/tmux 可启动、无 `.git` 残留）→ 验证 fcitx5 脚本在无图形会话下跳过 → 验证脚本可重复执行。日志输出至 `.tmp/test-logs/`。

边界说明：容器内无法验证输入法的实际候选框行为与字体渲染效果，该部分需在带桌面的虚拟机中人工验收一次。

## 🧰 维护

```bash
git submodule update --init --recursive   # 首次克隆后初始化子模块
./run.sh update                           # 拉取子模块远端更新（指针变更需自行提交）
./run.sh create                           # 生成离线包 dist/oh-my-linux_YYYYMMDD.tar.gz
```

## 📝 安装后提示

- **字体**：在终端设置中将字体切换为 `MesloLGS NF`，否则 Powerlevel10k 图标无法正常显示。
- **Powerlevel10k**：首次进入 Zsh 可运行 `p10k configure` 进行主题配置。
- **Tmux**：Oh My Tmux 默认前缀键同时支持 `Ctrl+a` 和 `Ctrl+b`。
- **输入法**：注销并重新登录后生效，`Ctrl+Space` 切换中英文。

## 📄 许可证

本仓库及其主导的脚本采用 MIT 许可证，完整条款见 [LICENSE](LICENSE)。

本项目包含的子模块 / 第三方组件各自遵循其自身许可证。
