# 硬盘与电池健康查看器

**Drive & Battery Health Viewer**

简体中文 | [English](README_EN.md)

一款用于查看 Windows 电脑硬盘状态、电池健康情况等设备信息的轻量级工具。

支持保存历史检测记录、导出检测报告，并提供硬盘与电池健康变化查看功能。


## 下载

请前往仓库的 [Releases](../../releases/latest) 页面下载最新版本。

当前版本：

**v1.0.4**

下载文件：

- `DriveBatteryHealthViewer_v1.0.4_Windows_x64.exe`
- `DriveBatteryHealthViewer_v1.0.4_Windows_x64_SHA256.txt`

本软件为 Windows x64 单文件程序，无需安装，下载后即可运行。


## 界面预览

### 主界面

![硬盘与电池健康查看器主界面](docs/screenshots/main-window-en.png)

### 历史记录

![历史记录界面](docs/screenshots/history-window-en.png)


## 主要功能

- 查看硬盘型号、容量、接口、固件版本和健康状态
- 读取 NVMe SMART 健康信息
- 查看硬盘温度、通电时间、通电次数、总读取量和总写入量
- 查看电池设计容量、当前满充容量、健康度和循环次数
- 自动保存并浏览历史检测记录
- 支持导出检测报告
- 支持隐藏硬盘和电池序列号不在报告中显示
- 支持简体中文、英语、俄语、法语、德语、韩语和日语
- 只读获取设备信息，不进行测速、擦写、修复或固件更新


## 使用方法

1. 下载最新版本 EXE 文件。
2. 双击运行程序。
3. 点击“刷新”检测当前硬盘和电池信息。
4. 可通过“导出报告”保存检测结果。
5. 分享检测报告前，建议启用“隐藏序列号”功能。


## 系统要求

- Windows 7 或更高版本
- 64 位操作系统
- 部分硬件信息读取可能需要管理员权限


## 兼容性说明

由于 Windows 系统接口和硬件厂商实现差异：

- RAID 模式可能无法读取完整 SMART 信息
- Intel VMD/RST 可能影响硬盘信息读取
- USB 转接设备可能无法提供完整硬盘数据
- 部分旧版 Windows 可能存在功能限制

以上情况通常属于系统或驱动限制，并不代表硬盘存在故障。


## 隐私说明

检测报告可能包含硬盘和电池序列号。

公开发布、转发或上传报告前，建议启用软件中的“隐藏序列号”功能，或手动删除相关信息。


## 从源码构建

本项目使用 Go 开发。

环境要求：

- Go 1.20 或更高版本

构建：

```bash
go test ./...
go build -o DriveBatteryHealthViewer.exe .
```


## 开源许可证

本项目依据 GNU General Public License v3.0 开源发布。

你可以自由使用、研究、修改和分发本项目。

发布修改版本时，需要遵守 GPL v3.0 协议，并保留原有版权声明。


## 作者

**程心**

- GitHub：[@xincheng1237](https://github.com/xincheng1237)
- 酷安：程心ChengXin
- QQ交流群：1040456137
- 联系邮箱：2680149724@qq.com


## 版权

© 2026 程心
