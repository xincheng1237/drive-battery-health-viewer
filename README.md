# 硬盘与电池健康查看器

**Drive & Battery Health Viewer**

简体中文 | [English](README_EN.md)

一款面向 Windows 与 macOS 的开源硬件健康查看工具。它展示硬盘状态、电池健康度与设备信息，并支持历史记录、批量管理、报告导出、序列号隐私保护和七种界面语言。

Windows 版使用 Go 开发；macOS 版采用原生 SwiftUI，提供同时兼容 Apple 芯片与 Intel Mac 的 Universal 2 应用。

## 下载

macOS 当前版本：**v1.1.0**；Windows 当前版本：**v1.0.6**。请前往 [Releases](../../releases/latest) 下载对应平台文件。

| 平台 | 下载文件 | 架构 | 系统要求 |
| --- | --- | --- | --- |
| macOS | [`DriveBatteryHealthViewer_v1.1.0_macOS_Universal.dmg`](../../releases/download/v1.1.0/DriveBatteryHealthViewer_v1.1.0_macOS_Universal.dmg) | Apple Silicon + Intel | macOS 13 Ventura 或更高版本 |
| Windows | [`DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup.exe`](../../releases/download/v1.0.6/DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup.exe) | x64 | Windows 7 SP1 或更高版本 |

### macOS 安装

1. 打开下载的 DMG。
2. 将“硬盘与电池健康查看器”拖入“应用程序”文件夹。
3. 从“应用程序”中启动软件。

当前 macOS 公开构建采用 ad-hoc 签名，尚未经过 Apple 公证。如果首次启动被系统阻止，请前往系统设置隐私与安全性确认打开。

### Windows 安装

Windows 当前最新版为 v1.0.6。推荐下载安装版并按照安装向导完成安装；如不希望安装，也可以下载免安装版直接运行。

- [下载安装版](../../releases/download/v1.0.6/DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup.exe)
- [下载免安装版](../../releases/download/v1.0.6/DriveBatteryHealthViewer_v1.0.6_Windows_x64.exe)

## 界面预览

### macOS 原生界面

![macOS 概览界面](docs/screenshots/macos-overview-zh.png)

![macOS 菜单栏充电保护](docs/screenshots/macos-charge-protection-menu-zh.png)

![macOS 历史记录界面](docs/screenshots/macos-history-zh.png)

### Windows 主界面

![Windows 版硬盘与电池健康查看器](docs/screenshots/main-window-en.png)

### Windows 历史记录

![Windows 历史记录界面](docs/screenshots/history-window-en.png)

## 主要功能

- 查看硬盘型号、容量、连接方式、固件、序列号和系统提供的 S.M.A.R.T. 状态
- 在硬件与系统允许时读取温度、工作时间、通电次数、总读取量和总写入量
- 查看电池制造商、类型、设计容量、满充容量、健康度、电压、循环次数、电量和充电状态
- 保存并浏览历史检测记录，支持多选、全选、批量导出和批量删除
- 复制或导出 UTF-8 健康报告
- 在界面、历史记录和导出报告中隐藏硬盘与电池序列号
- 支持简体中文、英语、俄语、法语、德语、韩语和日语
- 硬盘、S.M.A.R.T. 与健康信息保持只读，不进行测速、修复、擦除或固件更新
- macOS v1.1.0 为受支持的 Apple Silicon Mac 提供可选充电保护、菜单栏状态与快捷控制，并支持按时间范围导出隐私友好的诊断日志

## 平台说明

### macOS

- 原生 SwiftUI 界面，使用一个 Universal 2 安装包支持 Apple 芯片与 Intel Mac
- 支持 macOS 13 及以上版本，并适配深色模式、系统强调色、键盘操作和 VoiceOver
- 实时显示电池电量、充电状态，以及系统能够读取的硬盘和电池温度
- 支持历史记录、报告导出、序列号隐藏和隐私友好的诊断日志
- 内置只读 `smartctl`，不会测速、修复、擦除硬盘或更新固件

#### 充电保护兼容性

| 设备与系统 | 可用方式 |
| --- | --- |
| Apple Silicon + macOS 13 至 26.3（macOS 15.8 除外） | 支持 80% / 85% / 90% / 95% / 100% 多档充电上限 |
| Apple Silicon + macOS 15.8 | 使用 Apple 原生 80% 充电上限；选择 100% 可关闭充电保护 |
| Apple Silicon + macOS 26.4 及以上 | 优先推荐 macOS 原生功能，也可由用户明确选择使用本软件管理 |
| Intel Mac | 电池充电由 macOS 管理，不提供软件充电保护 |

充电保护默认关闭，仅在用户主动启用后工作。应用更新时会自动检查充电辅助程序版本，并在需要时完整替换旧版本。

外接硬盘能够显示的信息取决于 macOS、连接方式、硬盘盒和驱动是否提供底层数据。系统没有报告的项目会保持为空，不会估算或虚构。

“硬盘工作时间”由硬盘固件统计，不等同于电脑开机时间或实际使用时长。更详细的技术说明见 [`macos/README.md`](macos/README.md)。

### Windows

- RAID 模式或 Intel VMD/RST 可能影响完整 S.M.A.R.T. 信息读取
- USB 转接设备可能不会提供全部硬盘数据
- 部分旧版 Windows 或厂商驱动存在接口限制

这些情况通常属于系统、驱动、控制器或硬盘盒限制，并不代表硬件存在故障。

## 隐私说明

检测报告可能包含硬盘和电池序列号。公开发布、转发或上传报告前，建议启用软件中的“隐藏序列号”功能；macOS 版默认开启此保护。

## 从源码构建

### Windows

环境要求：Go 1.20 或更高版本。

```bash
go test ./...
go build -o DriveBatteryHealthViewer.exe .
```

### macOS

环境要求：macOS 13 或更高版本、Swift 5.10 或更高版本。

```bash
cd macos
swift test --disable-sandbox
./scripts/build-universal.sh
./scripts/build-dmg.sh
```

## 开源许可证

本项目依据 [GNU General Public License v3.0](LICENSE) 开源发布。你可以自由使用、研究、修改和分发本项目；发布修改版本时请遵守 GPL v3.0 并保留原有版权与许可证声明。

macOS 充电控制核心参考并重构了 TY-teo 的 [ChargeWatch](https://github.com/TY-teo/ChargeWatching) 中 AppleSMC、CHTE/CHIE 与安全恢复思路，并兼容旧式 CH0B/CH0C 控制键。原项目采用 MIT License，其版权、许可证和来源说明保存在 [`macos/Resources/ThirdParty/ChargeWatch/`](macos/Resources/ThirdParty/ChargeWatch/)。

## 作者

**程心**

- GitHub：[@xincheng1237](https://github.com/xincheng1237)
- 酷安：程心ChengXin
- QQ 交流群：1040456137
- 联系邮箱：2680149724@qq.com

## 版权

© 2026 程心
