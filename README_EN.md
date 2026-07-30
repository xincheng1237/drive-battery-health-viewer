# Drive & Battery Health Viewer

**硬盘与电池健康查看器**

[简体中文](README.md) | English

A lightweight utility for viewing drive status, battery health, and other device information on Windows PCs.

It supports saving and browsing historical scan records, exporting reports, and reviewing changes in drive and battery health over time.


## Download

Visit the [Releases](../../releases/latest) page to download the latest version.

Current version:

**v1.0.4**

Download files:

- `DriveBatteryHealthViewer_v1.0.4_Windows_x64.exe`
- `DriveBatteryHealthViewer_v1.0.4_Windows_x64_SHA256.txt`

This is a standalone Windows x64 application. No installation is required—download the EXE file and run it directly.


## Screenshots

### Main window

![Drive & Battery Health Viewer main window](docs/screenshots/main-window-en.png)

### History

![History window](docs/screenshots/history-window-en.png)


## Features

- View drive model, capacity, interface, firmware version, and health status
- Read NVMe SMART health information
- View drive temperature, power-on time, power cycles, total reads, and total writes
- View battery design capacity, current full-charge capacity, health percentage, and cycle count
- Automatically save and browse historical scan records
- Export scan reports
- Hide drive and battery serial numbers from the interface and reports
- Support Simplified Chinese, English, Russian, French, German, Korean, and Japanese
- Read device information only, without running benchmarks, writing data, performing repairs, or updating firmware


## Usage

1. Download the latest EXE file.
2. Double-click the file to run the application.
3. Click **Refresh** to scan the current drive and battery information.
4. Click **Export report** to save the scan results.
5. Before sharing a report, enable **Hide serial numbers** to protect device information.


## System Requirements

- Windows 7 or later
- 64-bit operating system
- Administrator privileges may be required to read some hardware information


## Compatibility

Due to differences in Windows system interfaces and hardware implementations:

- RAID mode may prevent access to complete SMART information
- Intel VMD/RST may affect drive information retrieval
- USB adapters may not expose complete drive data
- Some features may be limited on older versions of Windows

These conditions are generally caused by system or driver limitations and do not necessarily indicate a drive failure.


## Privacy

Scan reports may contain drive and battery serial numbers.

Before publishing, forwarding, or uploading a report, enable **Hide serial numbers** in the application or manually remove the relevant information.


## Building from Source

This project is developed in Go.

Requirements:

- Go 1.20 or later

Build and test:

```bash
go test ./...
go build -o DriveBatteryHealthViewer.exe .
```


## License

This project is released under the GNU General Public License v3.0.

You may freely use, study, modify, and distribute this project.

When distributing a modified version, you must comply with GPL v3.0 and retain the original copyright and license notices.


## Author

**ChengXin**

- GitHub: [@xincheng1237](https://github.com/xincheng1237)
- Coolapk: [程心ChengXin](https://www.coolapk.com/u/3594167)
- QQ group: 1040456137
- Email: 2680149724@qq.com


## Copyright

© 2026 ChengXin
