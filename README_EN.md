# Drive & Battery Health Viewer

**硬盘与电池健康查看器**

[简体中文](README.md) | English

An open-source hardware health viewer for Windows and macOS. It reads drive status, battery health, and device information without modifying hardware, and includes history and batch management, report export, update checking, serial-number privacy protection, and seven interface languages.

The Windows edition is written in Go. The macOS edition uses native SwiftUI and ships as one Universal 2 application for both Apple silicon and Intel Macs.

## Download

The current macOS and Windows release is **v1.0.6**. Visit [Releases](../../releases/latest) to download the appropriate platform file.

| Platform | Download | Architecture | Requirements |
| --- | --- | --- | --- |
| macOS | [`DriveBatteryHealthViewer_v1.0.6_macOS_Universal.dmg`](../../releases/download/v1.0.6/DriveBatteryHealthViewer_v1.0.6_macOS_Universal.dmg) | Apple silicon + Intel | macOS 13 Ventura or later |
| Windows | [Installer](../../releases/download/v1.0.6/DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup.exe) / [Portable](../../releases/download/v1.0.6/DriveBatteryHealthViewer_v1.0.6_Windows_x64.exe) | x64 | Windows 7 SP1 or later |

### Install on macOS

1. Open the downloaded DMG.
2. Drag **Drive & Battery Health Viewer** into **Applications**.
3. Launch the app from the Applications folder.

The current public macOS build uses an ad-hoc signature and has not been notarized by Apple. If macOS blocks the first launch, Control-click the app and choose **Open**, or approve it in **System Settings → Privacy & Security**. The project never asks you to disable system security features.

### Run on Windows

The Windows x64 edition is available as a standard installer and as a portable single executable; neither requires ZIP extraction. The installer is recommended for most users, while the portable EXE can be run directly. Administrator privileges may be needed for some hardware information. Windows 10 version 1809 and later use supported native storage interfaces; earlier versions automatically use compatibility readers while retaining the same page hierarchy, workflow, and core features.

## Screenshots

### Native macOS interface

![Drive & Battery Health Viewer for macOS](docs/screenshots/macos-overview-en.png)

### Windows main window

![Drive & Battery Health Viewer for Windows](docs/screenshots/main-window-en.png)

### Windows history

![Windows history view](docs/screenshots/history-window-en.png)

## Features

- View drive model, capacity, connection, firmware, serial number, and system-provided S.M.A.R.T. status
- Read temperature, operating time, power cycles, total reads, and total writes when exposed by the hardware and operating system
- View battery manufacturer, chemistry, design capacity, full-charge capacity, health, voltage, and cycle count; the Windows edition does not show live charge level or charging state
- Save and browse health history with multi-select, Select All, batch export, and batch deletion
- Copy or export UTF-8 reports and check GitHub for the latest stable release from the application menu
- Hide drive and battery serial numbers from the interface, history, and exported reports
- Support Simplified Chinese, English, Russian, French, German, Korean, and Japanese
- Read device information only: no benchmarks, writes, repairs, erases, or firmware updates

## Platform notes

### macOS

- Native SwiftUI interface with dark mode, system accent colors, keyboard support, and VoiceOver semantics
- Liquid Glass interface treatment on macOS 26 and later
- Live updates for battery level, charge/power state, and available drive and battery temperatures
- Optional automatic history saving when other hardware data is manually refreshed
- One Universal 2 package runs natively on Apple silicon and Intel Macs
- Bundled Universal 2 read-only `smartctl` can add drive details when macOS or an installed compatible driver exposes the low-level data
- See [`macos/README.md`](macos/README.md) for implementation details, build steps, and hardware-data limitations

macOS does not natively provide generic USB/SCSI S.M.A.R.T. passthrough. The bundled reader installs no driver and does not probe bridge modes unsupported by the system; it adds details only when macOS, a Thunderbolt connection, or an installed compatible driver exposes the low-level device. Data may still be unavailable when an enclosure blocks passthrough, RAID exposes only a logical device, or macOS denies the interface. Unavailable values are shown as not reported.

Drive operating time is reported by the drive firmware and may exclude periods when the controller is in a low-power state. It is not the same as the computer's power-on or actual usage time.

### Windows

- RAID mode and Intel VMD/RST may prevent complete S.M.A.R.T. access
- USB adapters may not expose all drive information
- Older Windows versions and vendor drivers may have interface limitations

These conditions are normally caused by the operating system, driver, controller, or enclosure and do not necessarily indicate a hardware failure.

## Privacy

Health reports may contain drive and battery serial numbers. Enable **Hide serial numbers** before publishing, forwarding, or uploading a report. The macOS edition enables this protection by default.

## Building from Source

### Windows

Requires Go 1.20 or later.

```bash
go test ./...
go build -o DriveBatteryHealthViewer.exe .
```

### macOS

Requires macOS 13 or later and Swift 5.10 or later.

```bash
cd macos
swift test --disable-sandbox
./scripts/build-universal.sh
./scripts/build-dmg.sh
```

## License

This project is released under the [GNU General Public License v3.0](LICENSE). You may use, study, modify, and distribute it. Modified distributions must comply with GPL v3.0 and retain the original copyright and license notices.

## Author

**ChengXin**

- GitHub: [@xincheng1237](https://github.com/xincheng1237)
- Coolapk: [程心ChengXin](https://www.coolapk.com/u/3594167)
- QQ group: 1040456137
- Email: 2680149724@qq.com

## Copyright

© 2026 ChengXin
