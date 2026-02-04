[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/Huanfiy/oh-my-terminal/blob/main/LICENSE)

# newpc_u22 — Linux 新机离线终端环境包

这是一个用于 Linux 新机的离线环境配置包，目标是快速搭建舒适的终端开发环境：**Zsh + Oh My Zsh + Powerlevel10k + 常用插件 + Tmux + Oh My Tmux**，并附带推荐[...

## 📦 包含组件

本项目以 Git submodules 的方式管理以下 5 个仓库（避免在主仓库中直接跟踪其文件内容）：

1. **[Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)**：Zsh 配置框架
2. **[Powerlevel10k](https://github.com/romkatv/powerlevel10k)**：Zsh 主题
3. **[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)**：命令自动建议
4. **[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)**：命令语法高亮
5. **[Oh My Tmux!](https://github.com/gpakosz/.tmux)**：Tmux 配置

资源文件：
- **`resources/MesloLGS NF Regular.ttf`**：Powerlevel10k 推荐字体（Nerd Font）

脚本：
- **`install_offline.sh`**：新机一键离线配置脚本
- **`run.sh`**：维护脚本（update/create）

## 📁 目录结构

```text
.
├── install_offline.sh
├── run.sh
├── README.md
├── libraries/                 # 5 个仓库（git submodules）
│   ├── oh-my-zsh/
│   ├── powerlevel10k/
│   ├── zsh-autosuggestions/
│   ├── zsh-syntax-highlighting/
│   └── oh-my-tmux/
└── resources/
    └── MesloLGS NF Regular.ttf
```

说明：
- `run.sh create` 会在打包时**临时拉取**最新版 Oh My Zsh 安装脚本，并写入离线包内的 `resources/omz_install.sh`（无网络则使用 `libraries/oh-my-zsh/tools/install.sh` [...]
- `install_offline.sh` 会优先使用 `resources/omz_install.sh` 生成 `.zshrc`，若不可用则回退到模板生成。

## 🛠️ 离线包使用方式（给新机器）

1. 解压离线包（例如 `newpc_u22_YYYYMMDD.tar.gz`）
2. 进入目录并执行：

```bash
chmod +x install_offline.sh
./install_offline.sh
```

### 前置依赖

脚本会尝试使用 `apt` 安装依赖（若机器完全断网，请提前准备/预装依赖，或配置离线源）：`zsh`、`tmux`、`git`、`fontconfig`。

## 🧰 维护者：更新与打包

### 首次克隆后初始化子模块

```bash
git submodule update --init --recursive
```

### 更新依赖仓库（子模块）

```bash
./run.sh update
```

说明：该命令会拉取子模块远端最新提交，并更新本地子模块指针；如需将更新记录到主仓库，请自行提交主仓库的 submodule 指针变更。

### 创建离线包（带日期后缀）

```bash
./run.sh create
```

产物：`dist/newpc_u22_YYYYMMDD.tar.gz`

## 📝 安装后提示

- **字体**：脚本会把字体安装到 `~/.local/share/fonts`，请在终端设置中将字体切换为 `MesloLGS NF`，否则 Powerlevel10k 图标可能无法显示。
- **Powerlevel10k**：首次进入 Zsh 可运行 `p10k configure` 进行主题配置。
- **Tmux**：Oh My Tmux 默认前缀键同时支持 `Ctrl+a` 和 `Ctrl+b`。

## 📄 许可证

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/Huanfiy/oh-my-terminal/blob/main/LICENSE)

本仓库及其主导的脚本采用 MIT 许可证。

本项目包含的子模块/第三方组件各自遵循其各自的许可证。有关本仓库的完整许可条款，请参阅项目根目录的 LICENSE 文件.