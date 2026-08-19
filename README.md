# DSH Web Desktop (DeepSeek Harness 桌面应用)

[![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)](https://github.com/Dinis0214/dsh-web-desktop)
[![Architecture](https://img.shields.io/badge/arch-Universal%20%7C%20x64%20%7C%20arm64-blue.svg)](https://github.com/Dinis0214/dsh-web-desktop)
[![dsh-plugin](https://img.shields.io/badge/tag-dsh--plugin-brightgreen.svg)](https://github.com/topics/dsh-plugin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

DeepSeek Harness (DSH) Web UI 的轻量跨平台原生桌面客户端，专为高效、沉浸的人机协同体验设计。

---

## 一、项目概述

本项目为 DeepSeek Harness (DSH) Web UI（默认运行在 `http://127.0.0.1:3080`）提供了专属的原生桌面客户端（全面支持 **macOS**、**Linux** 与 **Windows**）。

### 🌟 核心亮点

- **系统级原生轻量架构**：
  - **macOS**：采用 Swift (`AppKit + WebKit`) 原生单进程实现，产物仅 ~500KB，DMG 安装包仅 **~276KB**。
  - **Linux**：基于 `GTK3 + WebKit2GTK`，无缝适配 GNOME / KDE / XFCE 等各大主流桌面环境。
  - **Windows**：基于 Microsoft Edge `WebView2` 原生内核与 C# 启动器，安装包仅 **< 1MB**。
- **macOS Universal 2 双架构原生加速**：同时提供 Apple Silicon (`arm64`) 与 Intel (`x86_64`) 原生架构支持。
- **双运行模式无缝切换**：支持在菜单栏一键切换【常驻模式】与【随窗模式】，兼顾 24/7 后台挂机任务与轻量即用即走需求。
- **全自动依赖自愈与智能探测**：内置环境探测引擎，自动识别系统的 PATH、Homebrew、NVM、FNM、Volta 等多环境路径；执行一键安装时可自动配置 `@deepseek-ai/dsh` 核心依赖。
- **深度系统集成**：支持 macOS 原生应用菜单与全局快捷键、Linux 标准 XDG 桌面项与用户级 systemd 管理、Windows 系统托盘看护。

---

## 二、双运行模式说明

客户端提供了两种运行模式，满足不同工作场景下的资源与任务管理需求：

| 模式 | 运行机制 | 适用场景 |
| :--- | :--- | :--- |
| **常驻模式**<br>*(KeepAlive)*<br>**[默认启用]** | - **macOS**：由系统 `launchd` 进行守护（`KeepAlive: true, ThrottleInterval: 5s`）。<br>- **Linux**：由 `systemd --user` 用户服务进行常驻守护。<br>- **Windows**：系统托盘常驻守护 + 进程看护自动拉起。<br>- **关窗不中断**：关闭界面仅退出前端窗口，后台 AI 挂机任务和远程/局域网连接保持 24/7 运行；再次打开窗口即可瞬间接入。 | 长期挂机运行大任务、需要手机或远程设备随时随地通过网络访问。 |
| **随窗模式**<br>*(On-Demand)* | - 窗口为主进程。<br>- 打开客户端时启动后端服务并加载界面。<br>- **关闭窗口时立即停止后台服务**并释放端口与系统内存。 | 临时本地轻量使用、使用完毕后希望完全释放系统资源。 |

### 如何切换模式？
- **macOS**：在屏幕顶部主菜单栏点击 **【运行模式】**，勾选 `常驻模式 (Cmd+1)` 或 `随窗模式 (Cmd+2)`。
- **Linux / Windows**：在窗口菜单栏/标题栏点击 **【运行模式】** 即可实时切换。
- 偏好设置会自动保存至用户配置目录。

---

## 三、安装与环境就绪

项目安装脚本内置了**环境智能检测与自动安装引擎**：
- 安装时会自动探测本机是否已安装 `dsh`；
- 若未检测到，会自动调用包管理器（`npm` / `pnpm` / `yarn` / `bun` 等）自动为您全局安装 `@deepseek-ai/dsh`；
- 依赖就绪后自动完成桌面客户端的编译与部署。

---

## 四、跨平台快速安装指南

### 1. macOS 安装

#### 方式 A：一键编译并安装至系统
```bash
# 1. 编译 Universal 2 双架构二进制并组装应用
bash scripts/assemble.sh

# 2. 安装至 /Applications 并刷新系统缓存
bash scripts/install.sh
```

#### 方式 B：打包 DMG 安装映像（用于分发）
```bash
bash scripts/package-dmg.sh
# 生成的安装包位于 dist/DSH-Web-Desktop-macOS.dmg
```

---

### 2. Linux 安装

#### 安装系统依赖
- **Ubuntu / Debian**：
  ```bash
  sudo apt update
  sudo apt install -y libgtk-3-0 libwebkit2gtk-4.1-0 python3-gi
  ```
- **Fedora / RHEL**：
  ```bash
  sudo dnf install -y gtk3 webkit2gtk4.1 python3-gobject
  ```

#### 一键安装
```bash
# 安装至 ~/.local/bin，并注册桌面图标与 systemd 用户守护
bash scripts/install.sh
```

---

### 3. Windows 安装

#### 方式 A：编译原生 C# / WebView2 可执行文件
```powershell
# 需要 .NET 8.0 SDK
pwsh scripts/build-windows.ps1
pwsh scripts/install-windows.ps1
```

#### 方式 B：免编译快速启动
直接在 PowerShell 中运行启动器：
```powershell
powershell -ExecutionPolicy Bypass -File windows\launcher.ps1
```

---

## 五、目录结构

```
dsh-web-desktop/
├── app/                                   # macOS 原生 App 源码与资源
│   ├── Contents/
│   │   ├── Info.plist                     # macOS App 元数据
│   │   └── Resources/
│   │       └── icon.icns                  # macOS Squircle 图标
│   └── launcher/
│       └── main.swift                     # macOS Swift 原生启动器与生命周期
├── linux/                                 # Linux 原生客户端
│   └── src/
│       ├── main.c                         # Linux C + WebKitGTK 客户端源码
│       └── dsh-web.py                     # Linux Python + GTK 跨发行版客户端
├── windows/                               # Windows 原生客户端
│   ├── DshWeb.csproj                      # Windows .NET 8 WebView2 工程
│   ├── src/
│   │   └── Program.cs                     # Windows C# 原生主程序与托盘看护
│   └── launcher.ps1                       # Windows 免编译快速启动脚本
├── assets/
│   ├── ai.deepseek.dsh-web-desktop.plist  # macOS 登录自启模板
│   ├── dsh-web.desktop                    # Linux XDG 桌面项
│   ├── dsh-web.service                    # Linux systemd 用户守护服务模板
│   └── icons/                             # 包含 icns, ico, PNG 全套多分辨率图标
├── configs/
│   ├── ai.deepseek.dsh-web.plist.template # macOS KeepAlive 守护模板
│   └── config.example.json                # 客户端配置示例
├── scripts/                               # 全平台构建与安装运维脚本
│   ├── assemble.sh                        # 编译 macOS Universal 2 应用
│   ├── build-icon.sh                      # 重新绘制全套 icns, ico, PNG 图标
│   ├── build-linux.sh                     # 构建 Linux 客户端
│   ├── build-windows.ps1                  # 构建 Windows 客户端
│   ├── package-dmg.sh                     # 打包 macOS .dmg 安装包
│   ├── install.sh                         # 跨平台一键安装入口 (macOS & Linux)
│   ├── install-windows.ps1                # Windows 一键安装脚本
│   ├── uninstall.sh                       # 跨平台卸载与清理工具
│   ├── uninstall-windows.ps1              # Windows 卸载脚本
│   ├── enable-autostart.sh                # 启用开机自启
│   ├── disable-autostart.sh               # 禁用开机自启
│   ├── ensure-dsh.sh                      # 依赖检测与自动安装引擎
│   └── check-service.sh                   # 诊断 3080 端口与进程服务状态
├── .github/workflows/build.yml            # GitHub Actions 多平台自动化 CI/CD
├── LICENSE                                # MIT 开源协议
└── README.md                              # 项目说明文档
```

---

## 六、配置自定义（可选）

客户端配置文件路径：
- **macOS**：`~/Library/Application Support/DSH Web/config.json`
- **Linux**：`~/.config/dsh-web/config.json`
- **Windows**：`%APPDATA%\DSH Web\config.json`

```json
{
  "keepAlive": true,
  "port": 3080,
  "dshPath": null,
  "nodePath": null
}
```
- `keepAlive`：`true`（常驻模式） / `false`（随窗模式）。
- `port`：自定义服务监听端口（默认 `3080`）。
- `dshPath`：显式指定 `dsh` 可执行文件路径（留空则自动探测）。
- `nodePath`：显式指定 `node` 可执行文件路径（留空则自动探测）。

---

## 七、开源协议

本项目基于 [MIT License](LICENSE) 开源。
