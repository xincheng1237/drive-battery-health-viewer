# macOS 版硬盘与电池健康查看器

当前版本 **1.2**，适用于 macOS 13 及以上，支持 Apple 芯片与 Intel Mac。

[下载安装包](https://github.com/xincheng1237/drive-battery-health-viewer/releases/download/v1.2/DriveBatteryHealthViewer_v1.2_macOS_Universal.dmg) · [1.2 更新内容](https://github.com/xincheng1237/drive-battery-health-viewer/releases/tag/v1.2)

## 界面与操作

- **概览**：查看硬盘与电池健康、供电和充电状态。右上角提供刷新、保存报告、复制报告、打开报告和隐藏序列号操作。
- **历史**：查看保存的报告，使用 − / ＋ 调节报告文字大小；支持多选、全选、批量导出和删除。
- **设置**：语言、序列号显示、四档显示大小、历史保存与目录、充电保护选项、更新及关于信息。
- **更新**：在设置或应用菜单检查更新，阅读新版说明，下载后确认安装并重新启动。
- **显示菜单**：⌘1 / ⌘2 / ⌘3 切换页面，可选小、标准、大、特大四档显示大小；报告字号独立保存。
- 支持深浅色、系统强调色、键盘导航、VoiceOver，以及简体中文、英语、俄语、法语、德语、韩语、日语。

## 数据与报告

应用通过 macOS 的 diskutil、system_profiler、I/O Registry 和内置 smartctl 读取设备信息。电量、充电/供电状态和温度实时更新，完整检测可手动刷新并保存至历史。

硬盘字段包括型号、容量、连接方式、固件、S.M.A.R.T. 状态、温度、工作时间及读写统计；电池字段包括健康度、设计/满充容量（mAh 与 Wh）、循环次数、电压和温度。可用字段由设备、连接方式及系统提供，缺失项目显示“系统未报告”。

序列号默认隐藏，并同步用于界面、新保存的历史记录、复制和导出报告。报告使用 UTF-8 文本格式。

## 充电保护

| 设备与系统 | 操作 |
| --- | --- |
| Apple 芯片 + macOS 13 至 26.3（15.8 除外） | 80% / 85% / 90% / 95% / 100% 上限 |
| Apple 芯片 + macOS 15.8 | 原生 PowerUI 80% 上限，100% 恢复正常充电 |
| Apple 芯片 + macOS 26.4 及以上 | 系统管理，或在设置中选择本软件管理 |
| Intel Mac | 查看电池信息，使用 macOS 充电管理 |

首次启用通过管理员授权安装充电辅助程序。普通用户菜单栏代理提供状态和快捷操作。控制路径使用 CHTE，兼容旧式 CH0B/CH0C；macOS 15.8 使用 PowerUI。

“本次充满”完成后恢复原上限。系统“立即充满电”和校准分别识别，期间保留已设上限，并显示相应状态。当前校准通知映射适配 macOS 15.8.1（24H212）。状态依据见 [系统充电状态](docs/SYSTEM_CHARGING_STATES.md)。

确认上限保护正在生效且暂停充电时，概览给出原因说明；普通接电未充电保留系统状态提示。关闭保护或在设置中卸载辅助程序，会恢复正常充电。

## 诊断日志

“帮助 → 导出诊断日志…”可按时间范围合并应用与辅助程序日志。

| 来源 | 位置 |
| --- | --- |
| 应用 | `~/Library/Logs/DriveBatteryHealthViewer/` |
| 充电辅助程序 | `/Library/Logs/DriveBatteryHealthViewer/` |

JSON Lines 日志记录时间、级别、类别和事件，保留约 14 天、总量约 20 MB。日志使用脱敏路径。

## 从源码构建

环境：macOS 13 及以上，Swift 5.10 及以上。

```sh
cd macos
swift test --disable-sandbox
./scripts/test-powerui-bridge.sh
./scripts/build-dmg.sh
```

产物在 `macos/dist/`：

- `DriveBatteryHealthViewer_v1.2_macOS_Universal.dmg`
- `DriveBatteryHealthViewer_v1.2_macOS_Universal.zip`
- 对应 SHA-256 校验文件

主程序、smartctl 与 Sparkle 为 Universal 2，充电 Helper/Agent 为 arm64。打包脚本检查版本、架构、资源、嵌套签名与 DMG 内容。当前分发采用 ad-hoc 代码签名；应用内更新使用独立 Ed25519 签名。签名与发布步骤见 [应用内更新](docs/IN_APP_UPDATES.md)，本版验证见 [1.2 发布记录](docs/releases/1.2.md)。

## 开源组件

主项目采用 GPL v3。充电控制参考并重构 TY-teo 的 [ChargeWatch](https://github.com/TY-teo/ChargeWatching)；MIT 版权及来源说明保存在 `Resources/ThirdParty/ChargeWatch/`。smartmontools 7.5 的许可证和对应源代码、Sparkle 的许可证均随应用分发。
