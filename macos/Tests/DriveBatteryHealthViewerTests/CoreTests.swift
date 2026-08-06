import AppKit
import Foundation
import Testing
@testable import DriveBatteryHealthViewer

@Suite("Drive & Battery Health Viewer core")
struct CoreTests {
    @Test
    func testHealthStateThresholdsAndSMARTStatus() {
        #expect(healthState(forPercent: 100) == .good)
        #expect(healthState(forPercent: 80) == .good)
        #expect(healthState(forPercent: 79.9) == .warning)
        #expect(healthState(forPercent: 59.9) == .warning)
        #expect(healthState(forPercent: nil) == .unknown)
        #expect(healthState(forSMARTStatus: "Verified") == .good)
        #expect(healthState(forSMARTStatus: "Failing") == .critical)
    }

    @Test
    func testReportRedactsSerialNumbers() {
        let snapshot = sampleSnapshot()
        let visible = ReportRenderer.render(snapshot: snapshot, language: .english, hideSerials: false)
        let hidden = ReportRenderer.render(snapshot: snapshot, language: .english, hideSerials: true)
        #expect(visible.contains("DRIVE-SERIAL"))
        #expect(visible.contains("BATTERY-SERIAL"))
        #expect(!hidden.contains("DRIVE-SERIAL"))
        #expect(!hidden.contains("BATTERY-SERIAL"))
        #expect(hidden.contains("••••••••"))
    }

    @Test
    func testHistoryRoundTripAndDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(directory: root)
        let record = try store.save(snapshot: sampleSnapshot(), source: .refresh, hideSerials: true)
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == record.id)
        #expect(loaded.first?.snapshot.drives.first?.serialNumber == "••••••••")
        try store.delete(record)
        #expect(try store.load().isEmpty)
    }

    @Test
    func testDiskAndBatteryPropertyListsAreParsed() throws {
        let list = plist([
            "AllDisksAndPartitions": [["DeviceIdentifier": "disk0", "Size": 1_000_000_000_000 as UInt64]]
        ])
        let info = plist([
            "DeviceIdentifier": "disk0", "Whole": true, "VirtualOrPhysical": "Physical",
            "MediaName": "APPLE SSD", "TotalSize": 1_000_000_000_000 as UInt64,
            "BusProtocol": "PCI-Express", "SMARTStatus": "Verified", "SolidState": true, "Internal": true
        ])
        let battery = plist([[
            "DeviceName": "Mac Battery", "BatterySerialNumber": "BAT-1",
            "DesignCapacity": 5000, "AppleRawMaxCapacity": 4500, "CurrentCapacity": 77,
            "CycleCount": 234, "IsCharging": false, "ExternalConnected": true,
            "Voltage": 12_000,
            "BatteryData": [
                "Chemistry": "Li-ion",
                "MfgData": Data([0, 0, 4, 49, 57, 49, 52, 3, 65, 84, 76, 0])
            ]
        ]])
        let power = json([
            "SPPowerDataType": [["sppower_battery_health_info": ["sppower_battery_health_maximum_capacity": "80%"]]]
        ])
        let storageProfile = json([
            "SPNVMeDataType": [[
                "_name": "Apple SSD Controller",
                "_items": [[
                    "_name": "APPLE SSD",
                    "device_model": "APPLE SSD",
                    "device_revision": "561.100.",
                    "device_serial": "SSD-1"
                ]]
            ]]
        ])
        let runner = FixtureRunner(outputs: [
            FixtureRunner.key("/usr/sbin/diskutil", ["list", "-plist", "physical"]): .success(list),
            FixtureRunner.key("/usr/sbin/diskutil", ["info", "-plist", "disk0"]): .success(info),
            FixtureRunner.key("/usr/sbin/system_profiler", ["SPNVMeDataType", "SPSerialATADataType", "-json", "-detailLevel", "full"]): .success(storageProfile),
            FixtureRunner.key("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"]): .success(battery),
            FixtureRunner.key("/usr/sbin/system_profiler", ["SPPowerDataType", "-json", "-detailLevel", "full"]): .success(power)
        ])
        let scanner = HardwareScanner(runner: runner)
        let drives = try scanner.scanDrives()
        let batteries = try scanner.scanBatteries()
        #expect(drives.first?.model == "APPLE SSD")
        #expect(drives.first?.healthState == .good)
        #expect(drives.first?.capacityBytes == 1_000_000_000_000)
        #expect(drives.first?.serialNumber == "SSD-1")
        #expect(drives.first?.firmware == "561.100.")
        #expect(batteries.first?.healthPercent == 80)
        #expect(batteries.first?.capacityRatioPercent == 90)
        #expect(batteries.first?.manufacturer == "ATL")
        #expect(batteries.first?.chemistry == "Li-ion")
        #expect(batteries.first?.cycleCount == 234)
        let capacity = formattedBatteryCapacity(5000, voltageMillivolts: 12_000, language: .english)
        #expect(capacity == "5,000 mAh / 60.00 Wh")
        #expect(!capacity.contains("·"))
        #expect(!capacity.contains("≈"))
    }

    @Test
    func testNativeNVMeReaderRemainsAvailableAcrossRepeatedReadsWhenAvailable() {
        guard let first = nativeNVMeSMART(for: "disk0") else { return }
        #expect(first.percentageUsed <= 100)
        #expect(first.temperatureCelsius.map { (-30...150).contains($0) } ?? true)
        for _ in 0..<20 {
            let repeated = nativeNVMeSMART(for: "disk0")
            #expect(repeated != nil)
            #expect((repeated?.percentageUsed ?? 101) <= 100)
        }
    }

    @Test
    func testLastSuccessfulHardwareValuesSurviveTransientRefreshFailure() {
        let previous = sampleSnapshot()
        var fresh = previous
        fresh.generatedAt = previous.generatedAt.addingTimeInterval(60)
        fresh.drives[0].serialNumber = nil
        fresh.drives[0].firmware = nil
        fresh.drives[0].temperatureCelsius = nil
        fresh.drives[0].bytesRead = nil
        fresh.drives[0].bytesWritten = nil
        fresh.batteries[0].manufacturer = nil
        fresh.batteries[0].serialNumber = nil
        fresh.batteries[0].chemistry = nil
        fresh.batteries[0].temperatureCelsius = nil

        let merged = fresh.preservingUnavailableValues(from: previous)
        #expect(merged.generatedAt == fresh.generatedAt)
        #expect(merged.drives[0].serialNumber == "DRIVE-SERIAL")
        #expect(merged.drives[0].firmware == "1.0")
        #expect(merged.drives[0].temperatureCelsius == 35)
        #expect(merged.drives[0].bytesRead == 2_000_000_000)
        #expect(merged.drives[0].bytesWritten == 3_000_000_000)
        #expect(merged.batteries[0].manufacturer == "Apple")
        #expect(merged.batteries[0].serialNumber == "BATTERY-SERIAL")
        #expect(merged.batteries[0].chemistry == "Li-ion")
        #expect(merged.batteries[0].temperatureCelsius == 31)
    }

    @Test
    func testLiveHardwareUpdateChangesOnlyDynamicFields() {
        let snapshot = sampleSnapshot()
        let updated = snapshot.updatingLiveHardwareState(LiveHardwareState(
            battery: BatteryLiveState(
                chargePercent: 42,
                isCharging: true,
                externalConnected: false,
                temperatureCelsius: 29.5
            ),
            driveTemperatures: ["disk0": 44.5]
        ))
        #expect(updated.generatedAt == snapshot.generatedAt)
        #expect(updated.batteries[0].currentCapacityPercent == 42)
        #expect(updated.batteries[0].isCharging == true)
        #expect(updated.batteries[0].externalConnected == false)
        #expect(updated.batteries[0].healthPercent == snapshot.batteries[0].healthPercent)
        #expect(updated.batteries[0].temperatureCelsius == 29.5)
        #expect(updated.drives[0].temperatureCelsius == 44.5)
        #expect(updated.drives[0].bytesRead == snapshot.drives[0].bytesRead)
        #expect(updated.drives[0].bytesWritten == snapshot.drives[0].bytesWritten)
    }

    @Test @MainActor
    func testCriticalStringsAreLocalizedInEverySupportedLanguage() {
        let languages: [AppLanguage] = [.simplifiedChinese, .russian, .french, .german, .korean, .japanese]
        for language in languages {
            #expect(L10n.missingTranslationKeys(for: language).isEmpty)
            #expect(L10n.text("batteryVoltage", language) != "Battery voltage")
            #expect(L10n.text("changelog", language) != "What’s New")
            #expect(L10n.text("license", language) != "GNU GPL v3 License")
            #expect(L10n.text("selectAll", language) != "Select All")
            #expect(L10n.text("exportSelected", language) != "Export Selected")
            for key in MainMenuLocalizer.menuKeys {
                #expect(L10n.text(key, language) != key)
            }

            let report = ReportRenderer.render(snapshot: sampleSnapshot(), language: language, hideSerials: true)
            #expect(report.contains("v1.0.5"))
            #expect(report.contains("mAh /"))
            #expect(report.contains("••••••••"))
        }
        #expect(L10n.text("powerOnHours", .simplifiedChinese) == "工作时间")
        #expect(L10n.text("driveWorkingTimeExplanation", .simplifiedChinese) == "硬盘工作时间由硬盘固件统计，可能不包含控制器处于低功耗状态的时间，不等同于电脑开机或实际使用时长。")
        #expect(L10n.text("batteryHealthExplanation", .simplifiedChinese) == "电池健康度以 macOS 校准后的最大容量为准，受温度、充电管理、系统校准和取整影响，它与“满充容量÷设计容量”的直接计算结果可能存在细微差异。")
        #expect(L10n.text("powerConnectedNotCharging", .simplifiedChinese) == "已连接电源；当前电池已充满，或 macOS 根据当前状态暂时采用直接供电。")
    }

    @Test @MainActor
    func testMainMenuTitlesRelocalizeImmediately() {
        let menu = NSMenu()
        for title in ["Drive & Battery Health Viewer", "File", "View", "Health Report", "Window", "Help"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title)
            item.submenu = NSMenu(title: title)
            if title == "Health Report" {
                item.submenu?.addItem(NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "r"))
                item.submenu?.addItem(NSMenuItem(title: "Copy Report", action: nil, keyEquivalent: "c"))
            }
            menu.addItem(item)
        }

        MainMenuLocalizer.apply(to: menu, language: .simplifiedChinese)
        #expect(menu.items.map(\.title) == ["硬盘与电池健康查看器", "文件", "显示", "健康检测报告", "窗口", "帮助"])
        #expect(menu.items.map { $0.attributedTitle?.string ?? $0.title } == ["硬盘与电池健康查看器", "文件", "显示", "健康检测报告", "窗口", "帮助"])
        #expect(menu.items[3].submenu?.items.map(\.title) == ["刷新", "复制报告"])

        MainMenuLocalizer.apply(to: menu, language: .english)
        #expect(menu.items.map(\.title) == ["Drive & Battery Health Viewer", "File", "View", "Health Report", "Window", "Help"])
        #expect(menu.items[3].submenu?.items.map(\.title) == ["Refresh", "Copy Report"])
    }

    @Test @MainActor
    func testMenuDefinitionsAreIdempotentAndOrdered() {
        let expectedOrder = ["menuFile", "menuView", "report", "menuWindow", "menuHelp"]
        let first = MainMenuLocalizer.definitions(for: .simplifiedChinese)
        #expect(first.map(\.key) == expectedOrder)
        #expect(MainMenuLocalizer.menuOrder(for: .simplifiedChinese) == expectedOrder)
        for _ in 0..<20 {
            #expect(MainMenuLocalizer.definitions(for: .simplifiedChinese) == first)
            #expect(MainMenuLocalizer.menuOrder(for: .english) == expectedOrder)
        }
    }

    @Test @MainActor
    func testMenuLanguageRoundTripDoesNotRetainOldTitles() {
        let menu = NSMenu()
        let appItem = NSMenuItem(title: L10n.text("appName", .english), action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: appItem.title)
        menu.addItem(appItem)
        for definition in MainMenuLocalizer.definitions(for: .english) {
            let item = NSMenuItem(title: definition.title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: definition.title)
            menu.addItem(item)
        }

        for language in [AppLanguage.simplifiedChinese, .japanese, .german, .english, .simplifiedChinese] {
            MainMenuLocalizer.apply(to: menu, language: language)
            #expect(menu.items.map(\.title) == [L10n.text("appName", language)] + MainMenuLocalizer.definitions(for: language).map(\.title))
        }
    }

    @Test @MainActor
    func testNoProductionMenuDefinitionCanExposeInternalMarker() {
        for language in AppLanguage.allCases {
            #expect(MainMenuLocalizer.definitions(for: language).allSatisfy {
                !$0.title.hasPrefix("__DBHV_STANDARD_MENU_")
            })
        }
        let menu = NSMenu(title: "Main")
        for definition in MainMenuLocalizer.definitions(for: .english) {
            menu.addItem(NSMenuItem(title: definition.title, action: nil, keyEquivalent: ""))
        }
        #expect(!MainMenuLocalizer.containsInternalMarker(in: menu))
    }

    @Test @MainActor
    func testRepeatedMenuLocalizationPreservesSubmenusAndActions() {
        let menu = NSMenu(title: "Main")
        let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpSubmenu = NSMenu(title: "Help")
        let action = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        let about = NSMenuItem(title: "About", action: action, keyEquivalent: "")
        helpSubmenu.addItem(about)
        help.submenu = helpSubmenu
        menu.addItem(help)

        for _ in 0..<20 { MainMenuLocalizer.apply(to: menu, language: .simplifiedChinese) }

        #expect(menu.items.count == 1)
        #expect(menu.items[0].submenu?.items.count == 1)
        #expect(menu.items[0].submenu?.items[0].action == action)
        #expect(menu.items[0].submenu?.items[0].title == "关于“硬盘与电池健康查看器”")
    }

    @Test @MainActor
    func testCompleteStandardMenuRoundTripPreservesIdentityAndStructure() {
        let menu = representativeMainMenu()
        let itemIdentities = menuTreeItems(menu).map(ObjectIdentifier.init)
        let submenuIdentities = menuTreeSubmenus(menu).map(ObjectIdentifier.init)
        let actionSelectors = menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) }
        let itemCounts = menuTreeSubmenus(menu).map { $0.items.count }

        let languages: [AppLanguage] = [.simplifiedChinese, .russian, .french, .german, .korean, .japanese, .english]
        for language in languages {
            for _ in 0..<20 { MainMenuLocalizer.apply(to: menu, language: language) }
            #expect(menuTreeItems(menu).map(ObjectIdentifier.init) == itemIdentities)
            #expect(menuTreeSubmenus(menu).map(ObjectIdentifier.init) == submenuIdentities)
            #expect(menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) } == actionSelectors)
            #expect(menuTreeSubmenus(menu).map { $0.items.count } == itemCounts)
            #expect(!MainMenuLocalizer.containsInternalMarker(in: menu))
            #expect(menu.items.count == 6)
            #expect(menu.items[4].submenu?.items.count == 8)
            let windowTitles = menu.items[4].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            #expect(Set(windowTitles).count == windowTitles.count)
        }

        MainMenuLocalizer.apply(to: menu, language: .russian)
        #expect(menu.items.map(\.title) == ["Состояние накопителей и батареи", "Файл", "Вид", "Отчёт о состоянии", "Окно", "Справка"])
        #expect(menu.items[1].submenu?.items[0].title == "Экспортировать текущий отчёт")
        #expect(menu.items[2].submenu?.items[0].title == "Показать боковую панель")
        #expect(menu.items[4].submenu?.items[0].title == "Свернуть")
        #expect(menu.items[4].submenu?.items[4].title == "Перемещение и изменение размера")
        #expect(menu.items[5].submenu?.items[0].title == "Страница проекта")
    }

    @Test @MainActor
    func testProductionMenuTreeIsStableLocalizedAndFreeOfInjectedDuplicates() {
        let menu = MainMenuLocalizer.makeMenuForTesting(language: .english)
        let itemIdentities = menuTreeItems(menu).map(ObjectIdentifier.init)
        let submenuIdentities = menuTreeSubmenus(menu).map(ObjectIdentifier.init)
        let itemCounts = menuTreeSubmenus(menu).map { $0.items.count }
        let actionSelectors = menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) }

        #expect(menu.items.map(\.title) == [
            "Drive & Battery Health Viewer", "File", "View",
            "Health Report", "Window", "Help"
        ])
        #expect(menu.items[4].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "Minimize", "Zoom", "Enter/Exit Full Screen", "Bring All to Front"
        ])

        for language in [AppLanguage.simplifiedChinese, .english, .russian, .japanese, .german, .simplifiedChinese] {
            for _ in 0..<20 { MainMenuLocalizer.apply(to: menu, language: language) }
            #expect(menuTreeItems(menu).map(ObjectIdentifier.init) == itemIdentities)
            #expect(menuTreeSubmenus(menu).map(ObjectIdentifier.init) == submenuIdentities)
            #expect(menuTreeSubmenus(menu).map { $0.items.count } == itemCounts)
            #expect(menuTreeItems(menu).map { $0.action.map(NSStringFromSelector) } == actionSelectors)
            #expect(!MainMenuLocalizer.containsInternalMarker(in: menu))
            let windowTitles = menu.items[4].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            #expect(windowTitles.count == Set(windowTitles).count)
        }

        #expect(menu.items.map(\.title) == [
            "硬盘与电池健康查看器", "文件", "显示",
            "健康检测报告", "窗口", "帮助"
        ])
        #expect(menu.items[1].submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) == ["导出当前报告", "打开报告文件夹", "关闭窗口"])
        #expect(menu.items[5].submenu?.items.map(\.title) == ["项目主页", "反馈问题", "查看更新日志"])
    }

    @Test @MainActor
    func testChangelogKeeps104AndSeparates105FeaturesFromFixes() {
        for language in AppLanguage.allCases {
            let releases = ChangelogRelease.localized(for: language)
            #expect(releases.map(\.version) == ["1.0.5", "1.0.4", "1.0.0"])
            #expect(releases[0].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[0].sections[0].kind.symbol == "checkmark.circle.fill")
            #expect(releases[0].sections[1].kind.symbol == "wrench.and.screwdriver.fill")
            #expect(releases[0].sections.flatMap(\.items).allSatisfy { !$0.isEmpty })
            #expect(releases[1].sections.map(\.kind) == [.feature, .fix])
            #expect(releases[1].sections[0].items.count == 2)
            #expect(releases[1].sections[1].items.count == 2)
        }
        let chinese = ChangelogRelease.localized(for: .simplifiedChinese)
        #expect(chinese[0].sections[0].items.contains("新增对 macOS 26 及以上版本 Liquid Glass 界面效果的支持。"))
        #expect(chinese[0].sections[0].items.contains("新增检查更新功能。"))
        #expect(chinese[0].sections[1].items.allSatisfy { $0.hasPrefix("修复了") && $0.hasSuffix("的问题。") })
        #expect(chinese[1].sections[0].items == [
            "电量、充电状态、电源连接状态以及硬盘与电池温度改为自动实时更新。",
            "统一硬盘与电池字段顺序，容量改用 mAh / Wh，并完善健康度说明。"
        ])
        #expect(chinese[1].sections[1].items == [
            "修复重复刷新后 NVMe S.M.A.R.T. 数据消失的问题。",
            "调整应用图标安全边距。"
        ])
    }

    @Test
    func testReportsAndLiveUpdatesSupportDesktopMacWithoutBattery() {
        var desktop = sampleSnapshot()
        desktop.batteries = []
        for language in AppLanguage.allCases {
            let report = ReportRenderer.render(snapshot: desktop, language: language, hideSerials: true)
            #expect(report.contains("v1.0.5"))
            #expect(report.contains(desktop.computerName))
        }
        let updated = desktop.updatingLiveHardwareState(LiveHardwareState(
            battery: nil,
            driveTemperatures: ["disk0": 41]
        ))
        #expect(updated.batteries.isEmpty)
        #expect(updated.drives[0].temperatureCelsius == 41)
    }

    @Test @MainActor
    func testWindowAndHelpDefinitionsHaveUniqueStableEntries() {
        let definitions = MainMenuLocalizer.definitions(for: .english)
        #expect(Set(definitions.map(\.key)).count == definitions.count)
        #expect(definitions.filter(\.isSystemOwned).map(\.key) == MainMenuLocalizer.standardMenuKeys)
        #expect(definitions.filter { !$0.isSystemOwned }.map(\.key) == ["report"])
    }

    @Test @MainActor
    func testRequestedMenuCommandsAreLocalizedBoundAndEditableMenuIsAbsent() {
        let menu = MainMenuLocalizer.makeMenuForTesting(language: .simplifiedChinese)
        #expect(menu.items.map(\.title) == ["硬盘与电池健康查看器", "文件", "显示", "健康检测报告", "窗口", "帮助"])
        #expect(!menu.items.map(\.title).contains("编辑"))

        let fileItems = menu.items[1].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(fileItems.map(\.title) == ["导出当前报告", "打开报告文件夹", "关闭窗口"])
        #expect(fileItems[0].action.map(NSStringFromSelector) == "exportCurrentReport:")
        #expect(fileItems[1].action.map(NSStringFromSelector) == "openReportFolder:")

        let viewItems = menu.items[2].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(viewItems.map(\.title).contains("增大报告文字"))
        #expect(viewItems.map(\.title).contains("减小报告文字"))
        #expect(viewItems.map(\.title).contains("恢复默认文字大小"))

        let helpItems = menu.items[5].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(helpItems.map(\.title) == ["项目主页", "反馈问题", "查看更新日志"])
        #expect(helpItems.map { $0.action.map(NSStringFromSelector) } == ["openProjectHome:", "openIssueFeedback:", "showChangelog:"])

        let appItems = menu.items[0].submenu?.items.filter { !$0.isSeparatorItem } ?? []
        #expect(appItems.map(\.title).contains("检查更新…"))
        #expect(appItems.first(where: { $0.title == "检查更新…" })?.action.map(NSStringFromSelector) == "checkForUpdates:")
    }

    @Test
    func testUpdateVersionComparisonAndStableReleaseDecoding() throws {
        #expect(AppVersion("v1.0.6")! > AppVersion("1.0.5")!)
        #expect(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        #expect(AppVersion("1.0.5")! == AppVersion("1.0.5.0")!)
        #expect(AppVersion("1.0.5-beta")! == AppVersion("1.0.5")!)

        let data = Data(#"{"tag_name":"v1.0.6","html_url":"https://github.com/xincheng1237/drive-battery-health-viewer/releases/tag/v1.0.6","draft":false,"prerelease":false}"#.utf8)
        let release = try GitHubReleaseChecker.decodeRelease(from: data)
        #expect(release.version == "1.0.6")
        #expect(release.pageURL.absoluteString.hasSuffix("/releases/tag/v1.0.6"))
    }

    @Test @MainActor
    func testUpdateCheckPresentsNewReleaseAndRecognizesCurrentVersion() async {
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppLanguage.english.rawValue, forKey: "language")
        let release = AppReleaseInfo(
            version: "1.0.6",
            pageURL: URL(string: "https://github.com/xincheng1237/drive-battery-health-viewer/releases/tag/v1.0.6")!
        )

        let updateModel = AppModel(
            defaults: defaults,
            releaseChecker: StubReleaseChecker(release: release),
            currentAppVersion: "1.0.5"
        )
        await updateModel.checkForUpdatesNow()
        #expect(updateModel.availableUpdate?.version == "1.0.6")
        #expect(updateModel.availableUpdate?.currentVersion == "1.0.5")
        #expect(updateModel.alertMessage == nil)

        let currentModel = AppModel(
            defaults: defaults,
            releaseChecker: StubReleaseChecker(release: release),
            currentAppVersion: "1.0.6"
        )
        await currentModel.checkForUpdatesNow()
        #expect(currentModel.availableUpdate == nil)
        #expect(currentModel.alertMessage == "You’re using the latest version (v1.0.6).")
    }

    @Test @MainActor
    func testReportTextMenuAdjustmentsClampAndReset() {
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)
        model.reportTextSize = 22
        model.increaseReportTextSize()
        #expect(model.reportTextSize == 22)
        model.reportTextSize = 11
        model.decreaseReportTextSize()
        #expect(model.reportTextSize == 11)
        model.resetReportTextSize()
        #expect(model.reportTextSize == 13)
    }

    @Test @MainActor
    func testBatchHistoryExportAndDeleteOperateOnSelectedRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "DriveBatteryHealthViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        defaults.set(root.path, forKey: "historyDirectory")
        let store = HistoryStore(directory: root)
        let first = try store.save(snapshot: sampleSnapshot(), source: .refresh, hideSerials: true)
        var secondSnapshot = sampleSnapshot()
        secondSnapshot.generatedAt.addTimeInterval(60)
        _ = try store.save(snapshot: secondSnapshot, source: .refresh, hideSerials: true)

        let model = AppModel(defaults: defaults)
        #expect(model.history.count == 2)
        model.selectAllHistory()
        #expect(model.selectedHistoryIDs.count == 2)
        model.exportSelectedHistory(to: destination)

        let folders = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        #expect(folders.count == 1)
        let exported = try FileManager.default.contentsOfDirectory(at: folders[0], includingPropertiesForKeys: nil)
        #expect(exported.filter { $0.pathExtension == "txt" }.count == 2)

        model.deleteSelectedHistory(ids: model.selectedHistoryIDs)
        #expect(model.history.isEmpty)
        #expect(try store.load().isEmpty)
        _ = first
    }

    @Test
    func testLiveBatteryReaderReturnsSaneValuesWhenAvailable() {
        guard let state = readBatteryLiveState() else { return }
        #expect((0...100).contains(state.chargePercent))
        #expect(state.temperatureCelsius.map { (-30...120).contains($0) } ?? true)
    }

    @Test
    func testNativeBatteryStatusSymbolsAreAvailable() {
        #expect(ControlCenterBatteryAssets.hasAssets(for: "plug"))
        #expect(ControlCenterBatteryAssets.hasAssets(for: "bolt"))
        #expect(ControlCenterBatteryAssets.image(named: "battery-outline")?.size == NSSize(width: 23, height: 12))
        #expect(ControlCenterBatteryAssets.image(named: "battery-cap")?.size == NSSize(width: 2, height: 12))
        #expect(ControlCenterBatteryAssets.image(named: "battery-plug")?.size == NSSize(width: 11, height: 14))
        #expect(ControlCenterBatteryAssets.image(named: "battery-plug-mask")?.size == NSSize(width: 11, height: 14))
        #expect(NSImage(
            systemSymbolName: "battery.100percent.bolt",
            variableValue: 0.72,
            accessibilityDescription: nil
        ) != nil)
        #expect(NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "battery.75", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) != nil)
    }

    private func sampleSnapshot() -> HealthSnapshot {
        HealthSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            computerName: "Test Mac",
            drives: [DriveInfo(
                deviceIdentifier: "disk0", model: "Test SSD", serialNumber: "DRIVE-SERIAL", firmware: "1.0",
                protocolName: "NVMe", capacityBytes: 1_000_000_000_000, smartStatus: "Verified", healthState: .good,
                lifeRemainingPercent: 98, temperatureCelsius: 35, powerOnHours: 100, powerCycles: 20,
                bytesRead: 2_000_000_000, bytesWritten: 3_000_000_000, unsafeShutdowns: 1, mediaErrors: 0,
                isSolidState: true, isInternal: true, notes: []
            )],
            batteries: [BatteryInfo(
                name: "Battery", manufacturer: "Apple", serialNumber: "BATTERY-SERIAL", chemistry: "Li-ion",
                designCapacityMAh: 5000, fullChargeCapacityMAh: 4500, currentCapacityPercent: 75, cycleCount: 120,
                healthPercent: 90, capacityRatioPercent: 90, voltageMillivolts: 12_000, designVoltageMillivolts: 11_400,
                temperatureCelsius: 31, isCharging: false, externalConnected: true,
                healthState: .good, notes: []
            )]
        )
    }

    @MainActor
    private func representativeMainMenu() -> NSMenu {
        func top(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }

        func command(_ title: String, _ action: Selector? = nil, key: String = "") -> NSMenuItem {
            NSMenuItem(title: title, action: action, keyEquivalent: key)
        }

        let move = command("Move & Resize")
        move.submenu = NSMenu(title: "Move & Resize")
        ["Left", "Right", "Top", "Bottom", "Top Left", "Top Right", "Bottom Left", "Bottom Right", "Return to Previous Size"]
            .map { command($0) }
            .forEach(move.submenu!.addItem)

        let main = NSMenu(title: "Main")
        main.addItem(top("Drive & Battery Health Viewer", [
            command("About Drive & Battery Health Viewer", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            command("Settings…"), command("Services"), command("Hide Drive & Battery Health Viewer"),
            command("Hide Others"), command("Show All"), command("Quit Drive & Battery Health Viewer")
        ]))
        main.addItem(top("File", [command("Export Current Report"), command("Open Reports Folder"), command("Close Window", #selector(NSWindow.performClose(_:)), key: "w")]))
        main.addItem(top("View", [
            command("Show Sidebar"), command("Show Toolbar"), command("Customize Toolbar…"),
            command("Increase Report Text Size"), command("Decrease Report Text Size"), command("Reset Report Text Size"),
            command("Enter Full Screen")
        ]))
        main.addItem(top("Health Report", [command("Refresh", key: "r"), command("Copy Report", key: "c")]))
        main.addItem(top("Window", [
            command("Minimize"), command("Zoom"), command("Fill"), command("Center"), move,
            command("Full Screen Tile"), command("Remove Window from Set"), command("Bring All to Front")
        ]))
        main.addItem(top("Help", [command("Project Homepage"), command("Report an Issue"), command("View Release Notes")]))
        return main
    }

    @MainActor
    private func menuTreeItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(menuTreeItems) ?? []) }
    }

    @MainActor
    private func menuTreeSubmenus(_ menu: NSMenu) -> [NSMenu] {
        [menu] + menu.items.compactMap(\.submenu).flatMap(menuTreeSubmenus)
    }
}

private struct StubReleaseChecker: AppReleaseChecking {
    let release: AppReleaseInfo

    func latestStableRelease() async throws -> AppReleaseInfo { release }
}

private struct FixtureRunner: CommandRunning {
    let outputs: [String: CommandOutput]

    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        outputs[Self.key(executable, arguments)] ?? .failure
    }

    static func key(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).joined(separator: "\u{1F}")
    }
}

private extension CommandOutput {
    static func success(_ data: Data) -> CommandOutput { CommandOutput(data: data, errorText: "", status: 0) }
    static var failure: CommandOutput { CommandOutput(data: Data(), errorText: "fixture unavailable", status: 1) }
}

private func plist(_ value: Any) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}

private func json(_ value: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: value)
}
