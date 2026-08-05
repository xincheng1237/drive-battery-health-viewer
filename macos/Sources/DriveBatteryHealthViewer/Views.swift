import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsTextReport = false

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $model.destination) { destination in
                Label(model.t(destination.rawValue), systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle(model.t("appName"))
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } detail: {
            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar { toolbar }
        .alert(model.t("appName"), isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button(model.t("done"), role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let message = model.transientMessage {
                Text(message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.transientMessage)
        .sheet(isPresented: $showsTextReport) {
            if let snapshot = model.currentSnapshot {
                TextReportView(snapshot: snapshot)
                    .environmentObject(model)
            }
        }
        .task {
            model.startLiveHardwareMonitoring()
            if model.currentSnapshot == nil { model.refresh() }
        }
        .onDisappear { model.stopLiveHardwareMonitoring() }
        .onAppear { MainMenuLocalizer.apply(model.language) }
        .onChange(of: model.language) { language in
            MainMenuLocalizer.apply(language)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.destination ?? .overview {
        case .overview: OverviewView()
        case .history: HistoryView()
        case .settings: PreferencesView()
        case .about: AboutView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.destination == .overview {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.refresh) {
                    Label(model.isScanning ? model.t("refreshing") : model.t("refresh"), systemImage: "arrow.clockwise")
                }
                .id("refresh.\(model.language.rawValue)")
                .help(model.t("refresh"))
                .disabled(model.isScanning)

                Button(action: exportReport) {
                    Label(model.t("exportReport"), systemImage: "square.and.arrow.up")
                }
                .id("export.\(model.language.rawValue)")
                .help(model.t("exportReport"))
                .disabled(model.currentSnapshot == nil)

                Button(action: model.copyCurrentReport) {
                    Label(model.t("copyReport"), systemImage: "doc.on.doc")
                }
                .id("copy.\(model.language.rawValue)")
                .help(model.t("copyReport"))
                .disabled(model.currentSnapshot == nil)

                Button { showsTextReport = true } label: {
                    Label(model.t("report"), systemImage: "doc.text.magnifyingglass")
                }
                .id("report.\(model.language.rawValue)")
                .help(model.t("report"))
                .disabled(model.currentSnapshot == nil)

                Toggle(isOn: $model.hideSerials) {
                    Label(model.t("hideSerials"), systemImage: model.hideSerials ? "eye.slash" : "eye")
                }
                .id("privacy.\(model.language.rawValue)")
                .help(model.t("hideSerials"))
                .toggleStyle(.button)
            }
        }
    }

    private func exportReport() {
        guard let snapshot = model.currentSnapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "DriveBatteryHealth_\(formatter.string(from: snapshot.generatedAt)).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.exportCurrentReport(to: url)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isScanning && model.currentSnapshot == nil {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(model.t("refreshing")).foregroundStyle(.secondary)
                }
            } else if let snapshot = model.currentSnapshot {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        overviewHeader(snapshot)
                        hardwareSection(title: model.t("drives"), count: snapshot.drives.count, symbol: "internaldrive") {
                            if snapshot.drives.isEmpty {
                                EmptyCard(text: model.t("noDrives"), symbol: "externaldrive.badge.questionmark")
                            } else {
                                ForEach(snapshot.drives) { DriveCard(drive: $0) }
                            }
                        }
                        hardwareSection(title: model.t("batteries"), count: snapshot.batteries.count, symbol: "battery.75percent") {
                            if snapshot.batteries.isEmpty {
                                EmptyCard(text: model.t("noBattery"), symbol: "desktopcomputer")
                            } else {
                                ForEach(snapshot.batteries) { BatteryCard(battery: $0) }
                            }
                        }
                        if !snapshot.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(model.t("systemNotes"), systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                ForEach(snapshot.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                            }
                            .cardStyle()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.t("overviewLimitations"))
                            if !snapshot.batteries.isEmpty {
                                Text(model.t("batteryHealthExplanation"))
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                    }
                    .padding(28)
                    .frame(maxWidth: 1040)
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyState(
                    title: model.t("noScan"),
                    detail: model.t("noScanDetail"),
                    symbol: "gauge.with.dots.needle.33percent",
                    buttonTitle: model.t("refresh"),
                    action: model.refresh
                )
            }
        }
        .navigationTitle(model.t("overview"))
    }

    private func overviewHeader(_ snapshot: HealthSnapshot) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.computerName).font(.title2.weight(.semibold))
                Text(L10n.format("lastUpdated", model.language, snapshot.generatedAt.formattedReportDate()))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private func hardwareSection<Content: View>(title: String, count: Int, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol).font(.title3.weight(.semibold))
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            content()
        }
    }
}

struct DriveCard: View {
    @EnvironmentObject private var model: AppModel
    let drive: DriveInfo

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            HealthGauge(percent: drive.lifeRemainingPercent, state: drive.healthState, title: model.t("health"))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(drive.model).font(.headline)
                        Text(drive.deviceIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HealthBadge(state: drive.healthState)
                }
                Divider()
                DetailGrid(items: driveDetails)
            }
        }
        .cardStyle()
    }

    private var driveDetails: [DetailItem] {
        [
            DetailItem(model.t("capacity"), drive.capacityBytes > 0 ? drive.capacityBytes.formattedStorage : nil),
            DetailItem(model.t("protocol"), drive.protocolName),
            DetailItem(model.t("serialNumber"), serial(drive.serialNumber)),
            DetailItem(model.t("temperature"), drive.temperatureCelsius.map { String(format: "%.1f °C", $0) }),
            DetailItem(model.t("firmware"), drive.firmware),
            DetailItem(model.t("smartStatus"), drive.smartStatus),
            DetailItem(model.t("powerOnHours"), drive.powerOnHours.map { L10n.format("hours", model.language, $0) }),
            DetailItem(model.t("powerCycles"), drive.powerCycles.map(String.init)),
            DetailItem(model.t("totalRead"), drive.bytesRead.map { $0.formattedStorage }),
            DetailItem(model.t("totalWritten"), drive.bytesWritten.map { $0.formattedStorage })
        ]
    }

    private func serial(_ value: String?) -> String? {
        guard let value else { return nil }
        return model.hideSerials ? "••••••••" : value
    }
}

struct BatteryCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let battery: BatteryInfo

    private var showsPowerNotice: Bool {
        battery.externalConnected == true && battery.isCharging == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                HealthGauge(percent: battery.healthPercent, state: battery.healthState, title: model.t("health"))
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(battery.name).font(.headline)
                            if let current = battery.currentCapacityPercent {
                                HStack(spacing: 5) {
                                    BatteryStatusIcon(
                                        percent: current,
                                        isCharging: battery.isCharging == true,
                                        externalConnected: battery.externalConnected == true
                                    )
                                    Text(L10n.format("percent", model.language, Double(current)))
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HealthBadge(state: battery.healthState)
                    }
                    Divider()
                    DetailGrid(items: batteryDetails)
                }
            }
            if showsPowerNotice {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    Text(model.t("powerConnectedNotCharging"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(powerNoticeTransition)
            }
        }
        .cardStyle()
        .animation(powerNoticeAnimation, value: showsPowerNotice)
    }

    private var batteryDetails: [DetailItem] {
        [
            DetailItem(model.t("manufacturer"), battery.manufacturer),
            DetailItem(model.t("chemistry"), localizedBatteryType),
            DetailItem(model.t("serialNumber"), model.hideSerials && battery.serialNumber != nil ? "••••••••" : battery.serialNumber),
            DetailItem(model.t("temperature"), battery.temperatureCelsius.map { String(format: "%.1f °C", $0) }),
            DetailItem(model.t("designCapacity"), battery.designCapacityMAh.map { formattedBatteryCapacity($0, voltageMillivolts: battery.designVoltageMillivolts ?? battery.voltageMillivolts, language: model.language) }),
            DetailItem(model.t("fullChargeCapacity"), battery.fullChargeCapacityMAh.map { formattedBatteryCapacity($0, voltageMillivolts: battery.designVoltageMillivolts ?? battery.voltageMillivolts, language: model.language) }),
            DetailItem(model.t("cycleCount"), battery.cycleCount.map(String.init)),
            DetailItem(model.t("batteryVoltage"), battery.voltageMillivolts.map { formattedBatteryVoltage($0, language: model.language) }),
            DetailItem(model.t("charging"), battery.isCharging.map { model.t($0 ? "yes" : "no") }),
            DetailItem(model.t("connected"), battery.externalConnected.map { model.t($0 ? "yes" : "no") })
        ]
    }

    private var localizedBatteryType: String? {
        guard let type = battery.chemistry else { return nil }
        return type == "InternalBattery" ? model.t("internalBattery") : type
    }

    private var powerNoticeTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private var powerNoticeAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.34, dampingFraction: 0.88)
    }

}

enum ControlCenterBatteryAssets {
    private static let bundle = Bundle(path: "/System/Library/CoreServices/ControlCenter.app")
    private static let images: [String: NSImage] = {
        let names = [
            "battery-outline", "battery-cap",
            "battery-plug", "battery-plug-mask",
            "battery-bolt", "battery-bolt-mask"
        ]
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            bundle?.image(forResource: NSImage.Name(name)).map { (name, $0) }
        })
    }()

    static func image(named name: String) -> NSImage? {
        images[name]
    }

    static func hasAssets(for overlay: String?) -> Bool {
        guard images["battery-outline"] != nil, images["battery-cap"] != nil else { return false }
        guard let overlay else { return true }
        return images["battery-\(overlay)"] != nil && images["battery-\(overlay)-mask"] != nil
    }
}

struct BatteryStatusIcon: View {
    let percent: Int
    let isCharging: Bool
    let externalConnected: Bool

    private var fraction: Double {
        min(1, max(0, Double(percent) / 100))
    }

    private var overlayName: String? {
        if isCharging { return "bolt" }
        if externalConnected { return "plug" }
        return nil
    }

    var body: some View {
        Group {
            if ControlCenterBatteryAssets.hasAssets(for: overlayName) {
                controlCenterIcon
            } else {
                fallbackIcon
            }
        }
        .frame(width: 25, height: 14)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var controlCenterIcon: some View {
        ZStack(alignment: .topLeading) {
            if percent > 0 {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .frame(width: max(1.5, 19 * fraction), height: 8)
                    .offset(x: 2, y: 3)
            }
            controlCenterImage("battery-outline", width: 23, height: 12)
                .offset(y: 1)
            controlCenterImage("battery-cap", width: 2, height: 12)
                .offset(x: 23, y: 1)
            if let overlayName {
                controlCenterImage("battery-\(overlayName)-mask", width: 11, height: 14)
                    .offset(x: 6)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .overlay(alignment: .topLeading) {
            if let overlayName {
                controlCenterImage("battery-\(overlayName)", width: 11, height: 14)
                    .offset(x: 6)
            }
        }
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        if #available(macOS 14.0, *) {
            if isCharging {
                Image(systemName: "battery.100percent.bolt", variableValue: fraction)
            } else {
                Image(systemName: "battery.100percent", variableValue: fraction)
            }
        } else {
            Image(systemName: legacyBatterySymbol)
        }
    }

    private func controlCenterImage(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(nsImage: ControlCenterBatteryAssets.image(named: name)!)
            .renderingMode(.template)
            .resizable()
            .frame(width: width, height: height)
    }

    private var legacyBatterySymbol: String {
        switch percent {
        case 95...: return "battery.100"
        case 70...: return "battery.75"
        case 45...: return "battery.50"
        case 20...: return "battery.25"
        default: return "battery.0"
        }
    }
}

struct HealthGauge: View {
    let percent: Double?
    let state: HealthState
    let title: String

    private var fraction: Double { min(1, max(0, (percent ?? 0) / 100)) }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: percent == nil ? 0.12 : fraction)
                    .stroke(state.color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percent.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            .frame(width: 88, height: 88)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HealthBadge: View {
    @EnvironmentObject private var model: AppModel
    let state: HealthState

    var body: some View {
        Label(model.t(state.localizationKey), systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(state.color.opacity(0.12), in: Capsule())
    }
}

struct DetailItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String?
    init(_ label: String, _ value: String?) { self.label = label; self.value = value }
}

struct DetailGrid: View {
    @EnvironmentObject private var model: AppModel
    let items: [DetailItem]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 9) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index % 2 == 0 {
                    GridRow {
                        detail(item)
                        if index + 1 < items.count { detail(items[index + 1]) }
                    }
                }
            }
        }
    }

    private func detail(_ item: DetailItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.label).font(.caption).foregroundStyle(.secondary)
            Text(item.value ?? model.t("unavailable"))
                .font(.callout)
                .foregroundStyle(item.value == nil ? Color.secondary : Color.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Group {
            if model.history.isEmpty {
                EmptyState(title: model.t("historyEmpty"), detail: model.t("historyEmptyDetail"), symbol: "clock.arrow.circlepath")
            } else {
                HSplitView {
                    List(model.history, selection: $model.selectedHistoryID) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.snapshot.generatedAt.formattedReportDate()).font(.headline)
                            Text(record.snapshot.computerName).lineLimit(1)
                            Text(model.t(record.source == .refresh ? "sourceRefresh" : "sourceExport"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(record.id)
                    }
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 390)

                    if let record = model.selectedHistory {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.t("report")).font(.headline)
                                    Text(record.snapshot.generatedAt.formattedReportDate()).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                                    Label(model.t("delete"), systemImage: "trash")
                                }
                            }
                            .padding(16)
                            Divider()
                            ScrollView([.vertical, .horizontal]) {
                                Text(ReportRenderer.render(snapshot: record.snapshot, language: model.language, hideSerials: model.hideSerials))
                                    .font(.system(size: model.reportTextSize, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(18)
                            }
                        }
                        .frame(minWidth: 440)
                    }
                }
            }
        }
        .navigationTitle(model.t("history"))
        .confirmationDialog(model.t("deleteConfirm"), isPresented: $showsDeleteConfirmation) {
            Button(model.t("delete"), role: .destructive) { model.deleteSelectedHistory() }
            Button(model.t("cancel"), role: .cancel) { }
        } message: { Text(model.t("deleteDetail")) }
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section(model.t("appearance")) {
                Picker(model.t("language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(L10n.languageName(language, in: model.language)).tag(language)
                    }
                }
                Toggle(model.t("hideSerials"), isOn: $model.hideSerials)
                Text(model.t("privacyNotice")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(model.t("reportTextSize"))
                    Slider(value: $model.reportTextSize, in: 11...22, step: 1)
                    Text("\(Int(model.reportTextSize)) pt").monospacedDigit().frame(width: 42)
                }
            }

            Section(model.t("storage")) {
                Picker(model.t("saveMode"), selection: $model.historySaveMode) {
                    Text(model.t("saveOnRefresh")).tag(HistorySaveMode.refresh)
                    Text(model.t("saveOnExport")).tag(HistorySaveMode.export)
                }
                LabeledContent(model.t("historyLocation")) {
                    Text(model.historyDirectory.path)
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.t("openFolder")) { NSWorkspace.shared.open(model.historyDirectory) }
                    Button(model.t("chooseFolder"), action: chooseHistoryFolder)
                }
            }

            Section(model.t("dataAccess")) {
                Label(model.t("readOnlyNote"), systemImage: "checkmark.shield")
                Label(model.t("permissionNote"), systemImage: "externaldrive.badge.questionmark")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity, alignment: .top)
        .navigationTitle(model.t("settings"))
    }

    private func chooseHistoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.historyDirectory
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.historyDirectory = url
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsChangelog = false
    private let project = URL(string: "https://github.com/xincheng1237/drive-battery-health-viewer")!

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppMark()
                VStack(spacing: 7) {
                    Text(model.t("appName")).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                    Text(L10n.format("version", model.language, applicationVersion)).foregroundStyle(.secondary)
                }
                Text(model.t("aboutSummary"))
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: 620)

                VStack(alignment: .leading, spacing: 0) {
                    AboutRow(symbol: "person.crop.circle", title: model.t("developer"), value: model.t("author"))
                    Divider().padding(.leading, 46)
                    AboutLink(symbol: "chevron.left.forwardslash.chevron.right", title: model.t("projectHome"), url: project)
                    Divider().padding(.leading, 46)
                    AboutLink(symbol: "ladybug", title: model.t("issueFeedback"), url: project.appendingPathComponent("issues"))
                    Divider().padding(.leading, 46)
                    AboutButton(symbol: "sparkles", title: model.t("changelog")) { showsChangelog = true }
                    Divider().padding(.leading, 46)
                    AboutLink(symbol: "doc.badge.gearshape", title: model.t("license"), url: project.appendingPathComponent("blob/main/LICENSE"))
                    Divider().padding(.leading, 46)
                    AboutLink(symbol: "safari", title: model.t("coolapk"), url: URL(string: "https://www.coolapk.com/u/3594167")!)
                    Divider().padding(.leading, 46)
                    AboutRow(symbol: "person.3", title: model.t("qq"), value: "")
                    Divider().padding(.leading, 46)
                    AboutLink(symbol: "envelope", title: model.t("email"), url: URL(string: "mailto:2680149724@qq.com")!)
                }
                .padding(.horizontal, 16)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.separator.opacity(0.6)))
                .frame(maxWidth: 620)

                Text(model.t("readOnlyNote")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(model.t("copyright")).font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t("about"))
        .sheet(isPresented: $showsChangelog) {
            ChangelogView().environmentObject(model)
        }
    }
}

struct AppMark: View {
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
        .frame(width: 96, height: 96)
        .shadow(color: .blue.opacity(0.18), radius: 14, y: 6)
    }
}

struct AboutRow: View {
    let symbol: String
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.blue).frame(width: 22)
            Text(title)
            Spacer()
            if !value.isEmpty { Text(value).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 12)
    }
}

struct AboutLink: View {
    let symbol: String
    let title: String
    let url: URL
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.blue).frame(width: 22)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AboutButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.blue).frame(width: 22)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TextReportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let snapshot: HealthSnapshot

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.t("report")).font(.headline)
                Spacer()
                Button(model.t("copyReport"), action: model.copyCurrentReport)
                Button(model.t("done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(ReportRenderer.render(snapshot: snapshot, language: model.language, hideSerials: model.hideSerials))
                    .font(.system(size: model.reportTextSize, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

struct ChangelogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var releases: [ChangelogRelease] { ChangelogRelease.localized(for: model.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.t("changelog")).font(.title2.weight(.semibold))
                Spacer()
                Button(model.t("done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.format("version", model.language, release.version))
                                .font(.headline)
                            ForEach(release.items, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.primary, .green)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if release.id != releases.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 620, height: 500)
    }
}

private struct ChangelogRelease: Identifiable {
    var id: String { version }
    let version: String
    let items: [String]

    static func localized(for language: AppLanguage) -> [ChangelogRelease] {
        switch L10n.effective(language) {
        case .simplifiedChinese:
            return releases(
                current: [
                    "修复重复刷新后 NVMe S.M.A.R.T. 数据消失的问题，并保留上次成功读取的数据。",
                    "电量、充电状态、电源连接状态以及硬盘与电池温度改为自动实时更新。",
                    "统一硬盘与电池字段顺序，容量改用 mAh / Wh，并完善健康度说明。",
                    "调整应用图标安全边距。"
                ],
                initial: [
                    "推出原生 SwiftUI macOS 界面，支持深色模式与辅助功能。",
                    "加入硬盘与电池只读检测、历史记录、报告复制与导出。",
                    "支持 Intel 与 Apple 芯片的 Universal 2 构建。",
                    "支持七种语言、序列号隐私保护与报告字号调整。"
                ]
            )
        case .russian:
            return releases(
                current: ["Исправлено исчезновение данных NVMe S.M.A.R.T. после повторного обновления.", "Заряд, состояние зарядки, питание и температуры диска и батареи обновляются автоматически.", "Поля диска и батареи упорядочены; ёмкость показывается в mAh / Wh.", "Размер значка приведён к стандартам macOS."],
                initial: ["Нативный интерфейс SwiftUI с тёмным режимом и функциями доступности.", "Диагностика диска и батареи только для чтения, история и экспорт отчётов.", "Поддержка Intel и Apple silicon в Universal 2.", "Семь языков, защита серийных номеров и настройка текста отчёта."]
            )
        case .french:
            return releases(
                current: ["Correction de la disparition des données NVMe S.M.A.R.T. après plusieurs actualisations.", "Le niveau de batterie, la charge, l’alimentation et les températures du disque et de la batterie se mettent à jour automatiquement.", "Ordre des champs harmonisé et capacités affichées en mAh / Wh.", "Taille de l’icône alignée sur les conventions macOS."],
                initial: ["Interface SwiftUI native avec mode sombre et accessibilité.", "Lecture seule des disques et de la batterie, historique et export des rapports.", "Compatibilité Intel et Apple silicon avec Universal 2.", "Sept langues, confidentialité des numéros de série et taille de rapport réglable."]
            )
        case .german:
            return releases(
                current: ["Behoben: NVMe-S.M.A.R.T.-Daten verschwanden nach erneutem Aktualisieren.", "Akkustand, Ladezustand, Netzanschluss sowie Laufwerks- und Akkutemperatur werden automatisch aktualisiert.", "Feldreihenfolge vereinheitlicht und Kapazitäten als mAh / Wh dargestellt.", "Symbolgröße an macOS-Konventionen angepasst."],
                initial: ["Native SwiftUI-Oberfläche mit Dunkelmodus und Bedienungshilfen.", "Nur-Lese-Prüfung von Laufwerk und Akku, Verlauf und Berichtsexport.", "Universal-2-Unterstützung für Intel und Apple Chips.", "Sieben Sprachen, Schutz der Seriennummern und anpassbare Berichtsschrift."]
            )
        case .korean:
            return releases(
                current: ["반복 새로 고침 후 NVMe S.M.A.R.T. 데이터가 사라지는 문제를 수정했습니다.", "배터리 잔량, 충전 상태, 전원 연결 상태와 드라이브·배터리 온도가 자동으로 갱신됩니다.", "드라이브와 배터리 필드 순서를 통일하고 용량을 mAh / Wh로 표시합니다.", "앱 아이콘 크기를 macOS 규칙에 맞췄습니다."],
                initial: ["다크 모드와 손쉬운 사용을 지원하는 네이티브 SwiftUI 인터페이스.", "읽기 전용 드라이브·배터리 검사, 기록 및 보고서 내보내기.", "Intel 및 Apple 칩을 위한 Universal 2 지원.", "7개 언어, 일련번호 보호 및 보고서 글자 크기 조절."]
            )
        case .japanese:
            return releases(
                current: ["再更新後に NVMe S.M.A.R.T. データが消える問題を修正しました。", "バッテリー残量、充電状態、電源接続状態、ドライブとバッテリーの温度を自動更新します。", "ドライブとバッテリーの項目順を統一し、容量を mAh / Wh で表示します。", "アプリアイコンのサイズを macOS の慣例に合わせました。"],
                initial: ["ダークモードとアクセシビリティに対応したネイティブ SwiftUI UI。", "読み取り専用のドライブ・バッテリー検査、履歴、レポート書き出し。", "Intel と Apple チップに対応する Universal 2。", "7 言語、シリアル番号保護、レポート文字サイズ調整に対応。"]
            )
        case .english, .system:
            return releases(
                current: ["Fixed NVMe S.M.A.R.T. values disappearing after repeated refreshes.", "Battery level, charging state, power connection, and drive and battery temperatures now update automatically.", "Aligned drive and battery field order and display capacities as mAh / Wh.", "Adjusted the app icon safe area."],
                initial: ["Native SwiftUI interface with Dark Mode and accessibility support.", "Read-only drive and battery scans, history, report copy, and export.", "Universal 2 support for Intel and Apple silicon Macs.", "Seven languages, serial-number privacy, and adjustable report text."]
            )
        }
    }

    private static func releases(current: [String], initial: [String]) -> [ChangelogRelease] {
        [ChangelogRelease(version: "1.0.4", items: current), ChangelogRelease(version: "1.0.0", items: initial)]
    }
}

struct EmptyCard: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var buttonTitle: String?
    var action: (() -> Void)?

    init(title: String, detail: String, symbol: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.buttonTitle = buttonTitle; self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            if let buttonTitle, let action { Button(buttonTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4) }
        }
        .padding(32)
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.secondary.opacity(0.16)))
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

extension HealthState {
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    var localizationKey: String { rawValue }
}
