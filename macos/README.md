# Drive & Battery Health Viewer for macOS

这是“硬盘与电池健康查看器”的原生 macOS 版本，使用 SwiftUI 和 macOS 系统工具链开发，不依赖 Electron 或第三方运行时。

## 已实现功能

- 原生 SwiftUI 界面，支持深色模式、系统强调色、键盘操作与 VoiceOver 语义
- 只读查看物理硬盘型号、容量、连接方式、固态/内置属性与系统提供的 S.M.A.R.T. 状态
- 查看 Mac 电池制造商、序列号、设计容量、当前满充容量、健康度、电压、循环次数与充电状态；容量同时显示 mAh / Wh
- 电池电量、充电状态、电源连接状态以及硬盘与电池温度每 3 秒自动更新，其他硬件数据由手动刷新更新
- 刷新、复制完整文本报告、导出 UTF-8 文本报告
- 自动保存并浏览历史检测记录，可选择“每次刷新后”或“仅导出时”保存
- 历史记录支持多选、全选、批量导出到新文件夹和批量删除
- 左上角应用菜单支持检查 GitHub 最新正式版本，并在发现更新时打开对应 Release 下载页
- 在界面、历史记录、剪贴板和导出报告中隐藏序列号
- 跟随系统或切换简体中文、英语、俄语、法语、德语、韩语、日语
- 报告字号调整、历史目录选择、关于页、项目/反馈/许可证链接和更新日志
- 更新日志文字支持选择与复制
- macOS 26 及以上版本适配 Liquid Glass 界面效果
- 输出同时支持 Apple Silicon 与 Intel 的 Universal 2 应用
- 内置 Universal 2 版只读 `smartctl` 7.5；当 macOS 或已安装的兼容驱动公开底层设备时补充读取详细信息，许可证和完整对应源代码随应用分发
- Apple Silicon 充电保护：macOS 15.8 使用 PowerUI 原生 80% 路径；其他受支持组合提供 80% 至 100% 多档位，运行时检测 CHTE 或旧式 CH0B+CH0C，并保留“本次充满”
- 充电保护启用期间持续显示菜单栏状态图标，并根据保护中、到达上限、本次充满或需要注意切换状态。普通用户 LaunchAgent 负责图标与快捷控制，因此主应用完全退出后仍可操作
- 轻量 JSON Lines 诊断日志，支持从“帮助 → 导出诊断日志…”按时间范围合并导出主程序与 helper 日志

## 系统要求

- 运行：macOS 13 Ventura 或更高版本
- 构建：Swift 5.10 或更高版本（推荐 Xcode 16 或对应 Command Line Tools）

## 构建与测试

```bash
cd macos
swift test --disable-sandbox
./scripts/build-universal.sh
./scripts/build-dmg.sh
```

构建脚本生成：

- `DriveBatteryHealthViewer_v1.1.0_macOS_Universal.zip`
- `DriveBatteryHealthViewer_v1.1.0_macOS_Universal.dmg`

发布文件位于 `macos/dist/`。文件名包含版本、系统和 Universal 标识，便于在 GitHub Releases 中管理；DMG 提供“拖入应用程序”安装界面，安装后的应用始终为简洁的 `Drive & Battery Health Viewer.app`。

脚本会进行临时 ad-hoc 签名并验证包结构、Universal 架构和磁盘镜像校验和。仓库不包含开发者证书或私钥；官方公证发行时，应使用 Apple Developer ID 证书签名并通过 Apple 公证服务 notarize。

## 安装

1. 从 GitHub Releases 下载 Universal DMG。
2. 打开 DMG，将应用拖入“应用程序”文件夹。
3. 从“应用程序”中启动。

当前公开构建尚未经过 Apple 公证。如果首次打开被 Gatekeeper 阻止，可在访达中右键应用并选择“打开”，或在“系统设置 → 隐私与安全性”中确认打开；无需关闭系统安全功能。

## macOS 数据限制

硬盘、S.M.A.R.T. 与健康信息通过 macOS 自带的 `diskutil`、`system_profiler`、I/O Registry 以及随包提供的只读 `smartctl` 查询，不进行测速、修复、擦除或固件更新。`smartctl` 的许可证、声明和完整对应源代码位于应用资源中的 `ThirdParty/smartmontools/`。

macOS 原生不提供通用的 USB/SCSI S.M.A.R.T. 透传。应用不会安装内核扩展，也不会尝试 Darwin 后端不支持的 SAT/SNT 桥接模式；USB 设备只有在系统或用户另行安装的兼容驱动已公开底层数据时，才能补充读取对应 S.M.A.R.T. 项目。

macOS 不会向普通第三方应用开放所有硬件底层数据，因此以下项目可能显示“系统未报告”：

- Apple Silicon 内置 NVMe 的总读写量、通电时间、非安全关机次数等完整 SMART 日志
- 经过 USB/雷电硬盘盒连接的设备的厂商专用 SMART 字段
- 某些外接设备的固件、序列号或温度

无法读取的数据会显示为系统未报告。

界面中的“硬盘工作时间”由硬盘固件统计，可能不包含控制器处于低功耗状态的时间，不等同于电脑开机或实际使用时长。

## 隐私

序列号隐藏默认开启。开启状态下，新保存的历史记录只写入脱敏值；复制或导出的报告也不会包含原始硬盘和电池序列号。

## 电池充电保护（v1.1.0）

- Apple Silicon + macOS 13 至 26.3（macOS 15.8 除外）在检测到 CHTE 或旧式 CH0B+CH0C 能力后，提供 80% / 85% / 90% / 95% / 100% 多档位。Intel Mac 不开放。
- macOS 26.4 及以上默认折叠并优先推荐系统原生充电上限。用户仍可明确选择“继续使用本软件”；确认系统上限为 100% 并关闭“优化电池充电”后，再启用同样的 80% / 85% / 90% / 95% / 100% 多档位软件保护。在用户未明确完成该流程前，helper 不会控制充电。
- 首次启用通过管理员授权把 arm64 helper 安装到 `/Library/PrivilegedHelperTools/com.chengxin.drivebatteryhealthviewer.chargehelper`，LaunchDaemon 位于 `/Library/LaunchDaemons/`。新版应用首次启动时也会比较包内与已安装 helper，并在不一致时完整替换旧版；主应用始终以普通用户身份运行。
- 首次启用同时安装不提权的当前用户菜单栏代理到 `~/Library/Application Support/DriveBatteryHealthViewer/ChargeLimitAgent/`，LaunchAgent 位于 `~/Library/LaunchAgents/`；它只读取 helper 状态并写入经过校验的用户配置，不访问 SMC。
- 配置位于用户的 `~/Library/Application Support/DriveBatteryHealthViewer/ChargeProtection/`（目录 `0700`、文件 `0600`）；helper、LaunchDaemon、状态和日志由 root 管理，普通用户可读日志但不可修改。
- macOS 15.8 使用系统 PowerUI OBC：80% 用于启用原生上限，达到目标后保持适配器连接并停止电池充电；100% 用于关闭充电保护，85% / 90% / 95% 仍显示但置灰。其他支持的固件优先使用 CHTE，旧式 Apple Silicon 固件使用 CH0B+CH0C。CHIE 会隔离适配器，绝不作为普通限充 fallback。
- “本次充满”仅是持久化的临时 override：达到 100%/FullyCharged 后自动结束并恢复原固定档位，不包含周期性自动充满逻辑。
- 关闭保护或卸载 helper 前恢复正常充电；配置异常、电池读取失败、SMC 写入/校验失败和终止信号均触发优先恢复。

该功能参考并重构 [ChargeWatch](https://github.com/TY-teo/ChargeWatching) 的 AppleSMC、CHTE/CHIE 与 fail-safe 思路，并补充旧式 CH0B/CH0C 兼容路径；没有复制整个 App，也没有加入其周期性充满逻辑。ChargeWatch 的 MIT License 与作者 TY-teo 版权保存在 `Resources/ThirdParty/ChargeWatch/` 并随 App 分发。实际控制能力取决于 Mac 型号、系统与固件，仍必须在真实受支持设备上验证。

## 诊断日志

- 主程序：`~/Library/Logs/DriveBatteryHealthViewer/`（用户目录 `0700`、文件 `0600`）。
- 充电 helper：`/Library/Logs/DriveBatteryHealthViewer/`（root 写入、文件 `0644`，普通用户只读）。
- JSON Lines 记录时间、级别、分类和事件；Release 不写高频 debug，也不会每 3 秒记录电量。
- 默认不记录硬盘/电池序列号、报告正文、剪贴板、用户名、Apple ID 或完整私人路径；用户主目录统一脱敏为 `~`。
- 启动/写入时清理约 14 天前的记录，并限制总容量约 20 MB。
- “帮助 → 导出诊断日志…”默认最近 1 小时，可选择日期和时间；导出按时间排序合并 `[APP]` 与 `[CHARGE-HELPER]`，缺失来源会在文件中明确说明。
