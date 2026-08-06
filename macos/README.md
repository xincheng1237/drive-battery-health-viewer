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
- macOS 26 及以上版本适配 Liquid Glass 界面效果，macOS 13–15 保持原有原生卡片视觉
- 输出同时支持 Apple Silicon 与 Intel 的 Universal 2 应用

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

- `Drive & Battery Health Viewer-1.0.5-macOS-Universal.zip`
- `Drive & Battery Health Viewer-1.0.5-macOS-Universal.dmg`

发布文件位于 `macos/dist/`。文件名包含版本、系统和 Universal 标识，便于在 GitHub Releases 中管理；DMG 提供“拖入应用程序”安装界面，安装后的应用始终为简洁的 `Drive & Battery Health Viewer.app`。

脚本会进行临时 ad-hoc 签名并验证包结构、Universal 架构和磁盘镜像校验和。仓库不包含开发者证书或私钥；官方公证发行时，应使用 Apple Developer ID 证书签名并通过 Apple 公证服务 notarize。

## 安装

1. 从 GitHub Releases 下载 Universal DMG。
2. 打开 DMG，将应用拖入“应用程序”文件夹。
3. 从“应用程序”中启动。

当前公开构建尚未经过 Apple 公证。如果首次打开被 Gatekeeper 阻止，可在访达中右键应用并选择“打开”，或在“系统设置 → 隐私与安全性”中确认打开；无需关闭系统安全功能。

## macOS 数据限制

本应用通过 macOS 自带的 `diskutil`、`system_profiler` 和 I/O Registry 进行只读查询，不进行测速、写入、修复、擦除或固件更新。

macOS 不会向普通第三方应用开放所有硬件底层数据，因此以下项目可能显示“系统未报告”：

- Apple Silicon 内置 NVMe 的总读写量、通电时间、非安全关机次数等完整 SMART 日志
- 经过 USB/雷电硬盘盒连接的设备的厂商专用 SMART 字段
- 某些外接设备的固件、序列号或温度

应用不会用 `0` 或推测值代替无法读取的数据，也不会把“信息不可用”误判为硬件故障。

界面中的“硬盘工作时间”由硬盘固件统计，可能不包含控制器处于低功耗状态的时间，不等同于电脑开机或实际使用时长。

## 隐私

序列号隐藏默认开启。开启状态下，新保存的历史记录只写入脱敏值；复制或导出的报告也不会包含原始硬盘和电池序列号。
