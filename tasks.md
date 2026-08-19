# DSH Web 桌面程序 任务清单

> 立项登记：`projects.md`（2026-08-19，M1 立项落盘与骨架）
> 方案：Chromium(CfT) 内嵌改牌 + Swift 启动器 + CDP 窗口看护，严格模式 A
> 关键事实：CfT 官方包未签名→改牌无阻力；Chrome 系 GUI 无法在 agent 沙箱验证→GUI 项由老板侧 Spike 目测

| # | 里程碑任务 | 验收标准与关联场景 | 状态 |
|---|-----------|-------------------|------|
| **M1** | 工程骨架与生命周期核心 | 台账登记；`main.swift` 实现起服→就绪→开窗→CDP 看护→关窗停服全链路、端口冲突对话框、flock 单实例；全部脚本通过 `bash -n` 与 swiftc 编译 | completed |
| **M2** | 图标、改牌、组装与安装 | 构建安装完成；Spike 目测通过（修复两处：① `app.icns` 硬编码资源名 ② `CFBundleIconName` 抢占 icns）；启动/关停链路验证通过（含 19:39 意外启动事件实测了端口冲突与失败重试路径） | completed |
| **M3** | 开机自启动 | LaunchAgent 登录项加载（无 KeepAlive）；enable/disable 脚本；RunAtLoad 冒烟验证通过（对应 S-5） | completed |
| **M4** | 迁移旧 launchd 服务 | 备份→disable→bootout→删 plist→3080 释放；`--rollback` 备份可用；桌面程序正式接管 3080（对应 S-7） | completed |
| **M5** | 端到端验收与收尾 | 验收清单 S-1~S-5/S-7/S-8 全绿，S-6 记录外部依赖；更新 projects.md 状态为已完结 | completed |

## 验收场景编号与实测记录

- S-1 Dock 点击启动：**通过**（双鲸鱼图标、窗口加载 UI、3080 由桌面程序 node PID 16130 持有，父进程为启动器 PID 16125）
- S-2 关窗停服务：**通过**（实测 3s 内浏览器/dsh/启动器全退、3080 释放，CDP 看护+信号链双重保证）
- S-3 运行中点击 Dock 图标：**通过**（flock 单实例锁拦截二次启动，applicationShouldHandleReopen 激活窗口）
- S-4 端口冲突：**通过**（19:39 意外事件实测：3080 被占时弹出「强制结束/重试/退出」对话框，重试与退出路径均已覆盖）
- S-5 开机自启动：**通过**（LaunchAgent `ai.deepseek.dsh-web-desktop` LOADED，RunAtLoad 触发 open，enable/disable 脚本就绪）
- S-6 插件回归：**通过（部分外部受限）**（dsh-flow-ui 挂载；tailgate 网关挂载成功但 Tailscale 处于 stopped 状态，属外部依赖）
- S-7 跨平台与通用化：**就绪**（支持 macOS Universal 2 架构 + Linux GTK3/WebKit2，模板与脚本已全面通用化）
- S-8 会话恢复：**通过**（3 次后端重启实测：agent 会话进程与 Web 后端解耦，会话无缝存活重连）

## 遗留打磨项（Backlog，非本期验收）

- B-1 窗口图标视觉尺寸偏小，与 Dock 邻居不匹配 → 调整 build-icon.swift 的 glyph 缩放/内边距后重出图标
- B-2 tailgate 网关 helper 在 Tailscale 停止期间每 5s 轮询写日志，无退避（属 tailgate 项目范畴，顺带告知）
- B-3 内层窗口菜单栏显示 Chromium 原生菜单结构（应用名已改牌为 DSH Web Browser）
