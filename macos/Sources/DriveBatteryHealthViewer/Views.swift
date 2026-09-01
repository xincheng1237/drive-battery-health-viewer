import AppKit
import ChargeProtectionCore
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    if model.showsVersionUpdatePrompt {
                        VersionUpdateTip()
                            .environmentObject(model)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
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
        .alert(
            model.t("chargeHelperAuthorizationTitle"),
            isPresented: Binding(
                get: { model.chargeProtection.showsHelperUpdateAuthorizationPrompt },
                set: { model.chargeProtection.showsHelperUpdateAuthorizationPrompt = $0 }
            )
        ) {
            Button(model.t("continueAuthorization")) {
                model.chargeProtection.continueInstalledHelperUpdate()
            }
            Button(model.t("cancel"), role: .cancel) {
                model.chargeProtection.showsHelperUpdateAuthorizationPrompt = false
            }
        } message: {
            Text(model.t("chargeHelperInstallAuthorizationMessage"))
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
        .sheet(item: $model.availableUpdate) { update in
            UpdateAvailableView(update: update)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showsDiagnosticExport) {
            DiagnosticExportView()
                .environmentObject(model)
        }
        .animation(.easeOut(duration: 0.22), value: model.showsVersionUpdatePrompt)
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
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(model.isScanning ? 0 : 1)
                        if model.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    // Keep the idle icon and progress indicator in one fixed
                    // toolbar slot so scrolling or window resizing cannot
                    // make the spinner appear above or below the button.
                    .frame(width: 16, height: 16, alignment: .center)
                }
                .id("refresh.\(model.language.rawValue)")
                .accessibilityLabel(model.isScanning ? model.t("refreshing") : model.t("refresh"))
                .help(model.t("refresh"))
                .disabled(model.isScanning)

                Button(action: model.presentExportCurrentReportPanel) {
                    Label(model.t("exportReport"), systemImage: "square.and.arrow.down")
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

}

/// A compact, nonmodal in-app tip. It follows Apple's guidance to keep
/// optional onboarding contextual and dismissible, and never steals focus or
/// blocks the user's current work like a launch alert or sheet would.
private struct VersionUpdateTip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.format("versionUpdatePromptTitle", model.language, model.displayedAppVersion))
                    .font(.headline)
                Text(model.t("versionUpdatePromptMessage"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(model.t("viewChangelog")) {
                model.presentChangelogFromVersionUpdatePrompt()
            }
            .buttonStyle(.bordered)

            Button {
                model.dismissVersionUpdatePrompt()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.t("dismissVersionUpdatePrompt"))
            .accessibilityLabel(model.t("dismissVersionUpdatePrompt"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .dbhvCardSurface(cornerRadius: 11)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct UpdateAvailableView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let update: AvailableAppUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text(L10n.format("updateAvailableTitle", model.language, update.version))
                    .font(.title2.weight(.semibold))
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.format("currentVersionLabel", model.language, update.currentVersion))
                Text(L10n.format("latestVersionLabel", model.language, update.version))
                    .fontWeight(.medium)
            }

            HStack {
                Spacer()
                Button(model.t("later"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.t("downloadFromGitHub")) {
                    NSWorkspace.shared.open(update.pageURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 450)
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
                                if snapshot.warnings.contains(where: { $0.hasPrefix("Battery information:") }) {
                                    EmptyCard(text: model.t("noBattery"), symbol: "battery.0percent")
                                } else {
                                    DesktopMacEmptyCard()
                                }
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
                            if !snapshot.drives.isEmpty {
                                Text(model.t("driveWorkingTimeExplanation"))
                            }
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
            DetailItem(
                model.t("powerOnHours"),
                drive.powerOnHours.map { L10n.format("hours", model.language, $0) },
                helpText: drive.isInternal == true && drive.isSolidState == true ? model.t("driveWorkingTimeDetail") : nil
            ),
            DetailItem(model.t("powerCycles"), drive.powerCycles.map(String.init)),
            DetailItem(model.t("totalRead"), drive.bytesRead.map { $0.formattedStorage }),
            DetailItem(model.t("totalWritten"), drive.bytesWritten.map { $0.formattedStorage }),
            DetailItem(model.t("unsafeShutdowns"), drive.unsafeShutdowns.map(String.init)),
            DetailItem(model.t("errorLogEntries"), drive.errorLogEntries.map(String.init))
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
                    ChargeProtectionSection(manager: model.chargeProtection)
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

struct ChargeLimitPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var manager: ChargeProtectionManager
    var onSelect: ((Int) -> Bool)?
    @State private var draggingValue: Double?
    @State private var presentedIndex: Double?

    private let percentages = [80, 85, 90, 95, 100]

    init(
        manager: ChargeProtectionManager,
        onSelect: ((Int) -> Bool)? = nil
    ) {
        self.manager = manager
        self.onSelect = onSelect
    }

    var body: some View {
        standardPicker
        .onAppear {
            if presentedIndex == nil { presentedIndex = Double(selectedIndex) }
        }
        .onChange(of: manager.displayedLimitPercentage) { _ in
            guard draggingValue == nil else { return }
            let target = Double(selectedIndex)
            guard presentedIndex != target else { return }
            if presentedIndex == nil {
                presentedIndex = target
            } else {
                withAnimation(selectionAnimation) { presentedIndex = target }
            }
        }
    }

    private var standardPicker: some View {
        VStack(spacing: 6) {
            chargeLimitTrack

            HStack(spacing: 0) {
                ForEach(Array(percentages.enumerated()), id: \.offset) { index, percentage in
                    Button { select(index: index) } label: {
                        optionLabel(percentage)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!manager.isLimitSelectable(percentage))
                    .help("\(percentage)%")
                    .accessibilityLabel("\(model.t("fixedChargeLimit")) \(percentage)%")
                    .opacity(manager.isLimitSelectable(percentage) ? 1 : 0.38)
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
            }
            .frame(height: 38)
        }
    }

    private func optionLabel(_ percentage: Int) -> some View {
        VStack(spacing: 2) {
            ChargeLimitBatteryIcon(percent: percentage)
            Text("\(percentage)%")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(isSelected(percentage) ? Color.accentColor : Color.secondary)
        .fontWeight(isSelected(percentage) ? .semibold : .regular)
        .frame(maxWidth: .infinity, minHeight: 34)
    }

    private var selectedIndex: Int {
        percentages.firstIndex(of: manager.displayedLimitPercentage) ?? percentages.count - 1
    }

    private var displayedValue: Double {
        draggingValue ?? presentedIndex ?? Double(selectedIndex)
    }

    private var displayedIndex: Int {
        min(percentages.count - 1, max(0, Int(displayedValue.rounded())))
    }

    private var chargeLimitTrack: some View {
        GeometryReader { geometry in
            let trackInset = trackInset(for: geometry.size.width)
            let trackWidth = max(0, geometry.size.width - (trackInset * 2))
            let thumbX = trackInset + trackWidth * CGFloat(displayedValue) /
                CGFloat(percentages.count - 1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 4)
                    .padding(.horizontal, trackInset)

                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(width: max(0, thumbX - trackInset), height: 4)
                    .offset(x: trackInset)

                ForEach(percentages.indices, id: \.self) { index in
                    let isSelectable = manager.isLimitSelectable(percentages[index])
                    Circle()
                        .fill(
                            isSelectable && index <= displayedIndex
                                ? Color.accentColor
                                : Color(nsColor: .separatorColor)
                        )
                        .frame(width: 5, height: 5)
                        .opacity(isSelectable ? 1 : 0.38)
                        .position(x: labelPosition(for: index, width: geometry.size.width), y: 11)
                }

                Circle()
                    .fill(.background)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.5)
                    .position(x: thumbX, y: 11)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        let clampedX = min(
                            geometry.size.width - trackInset,
                            max(trackInset, gesture.location.x)
                        )
                        let continuousValue = Double(
                            (clampedX - trackInset) / max(1, trackWidth)
                        ) * Double(percentages.count - 1)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { draggingValue = continuousValue }
                    }
                    .onEnded { gesture in
                        let clampedX = min(
                            geometry.size.width - trackInset,
                            max(trackInset, gesture.location.x)
                        )
                        let value = Double(
                            (clampedX - trackInset) / max(1, trackWidth)
                        ) * Double(percentages.count - 1)
                        settle(on: Int(value.rounded()))
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.t("fixedChargeLimit"))
        .accessibilityValue("\(percentages[displayedIndex])%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settle(on: nextSelectableIndex(after: displayedIndex))
            case .decrement: settle(on: previousSelectableIndex(before: displayedIndex))
            @unknown default: break
            }
        }
    }

    private func select(index: Int) {
        settle(on: index)
    }

    private func settle(on index: Int) {
        guard percentages.indices.contains(index),
              manager.isLimitSelectable(percentages[index]) else {
            withAnimation(selectionAnimation) {
                draggingValue = nil
                presentedIndex = Double(selectedIndex)
            }
            return
        }
        let accepted = commit(index: index)
        withAnimation(selectionAnimation) {
            draggingValue = nil
            presentedIndex = accepted ? Double(index) : Double(selectedIndex)
        }
    }

    private func commit(index: Int) -> Bool {
        guard percentages.indices.contains(index) else { return false }
        let percentage = percentages[index]
        if let onSelect { return onSelect(percentage) }
        manager.selectDisplayedLimit(percentage)
        return true
    }

    private func nextSelectableIndex(after index: Int) -> Int {
        percentages.indices.first {
            $0 > index && manager.isLimitSelectable(percentages[$0])
        } ?? index
    }

    private func previousSelectableIndex(before index: Int) -> Int {
        percentages.indices.reversed().first {
            $0 < index && manager.isLimitSelectable(percentages[$0])
        } ?? index
    }

    private func isSelected(_ percentage: Int) -> Bool {
        percentages[displayedIndex] == percentage
    }

    private func labelPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard !percentages.isEmpty else { return width / 2 }
        return width * (CGFloat(index) + 0.5) / CGFloat(percentages.count)
    }

    private func trackInset(for width: CGFloat) -> CGFloat {
        guard !percentages.isEmpty else { return 0 }
        return width / (CGFloat(percentages.count) * 2)
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86)
    }
}

private struct ChargeLimitBatteryIcon: View {
    let percent: Int

    var body: some View {
        BatteryStatusIcon(percent: percent, isCharging: false, externalConnected: false)
    }
}

private enum PendingChargeAuthorizationAction {
    case enable
    case selectLimit(Int)
}

struct ChargeProtectionSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var manager: ChargeProtectionManager
    @State private var pendingAuthorizationAction: PendingChargeAuthorizationAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label(model.t("chargeProtection"), systemImage: "battery.100percent.bolt")
                .font(.subheadline.weight(.semibold))
            if manager.isSectionExpanded {
                Group {
                    switch manager.availability {
                    case .unsupportedHardware:
                        intelManagedContent
                    case .systemPreferred:
                        systemPreferredContent
                    case .softwareAvailable, .softwareManaged:
                        eligibleControls
                    }
                }
                .transition(disclosureTransition)
            }

            Button {
                withAnimation(disclosureAnimation) {
                    manager.toggleSectionExpanded()
                }
            } label: {
                Image(systemName: manager.isSectionExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.t(manager.isSectionExpanded ? "collapseChargeProtection" : "expandChargeProtection"))
            .accessibilityLabel(model.t(manager.isSectionExpanded ? "collapseChargeProtection" : "expandChargeProtection"))
        }
        .animation(disclosureAnimation, value: manager.isSectionExpanded)
        .alert(
            model.t("chargeMigrationTitle"),
            isPresented: Binding(
                get: { manager.showsUpgradeMigrationPrompt },
                set: { _ in }
            )
        ) {
            Button(model.t("switchToSystemCharging")) {
                manager.switchToSystemPreferred()
            }
            Button(model.t("continueSoftwareCharging")) {
                manager.continueSoftwareAfterUpgrade()
            }
        } message: {
            Text(model.t("chargeMigrationMessage"))
        }
        .alert(
            model.t("chargeHelperAuthorizationTitle"),
            isPresented: Binding(
                get: { pendingAuthorizationAction != nil },
                set: { if !$0 { pendingAuthorizationAction = nil } }
            )
        ) {
            Button(model.t("continueAuthorization")) {
                performPendingAuthorizationAction()
            }
            Button(model.t("cancel"), role: .cancel) {
                pendingAuthorizationAction = nil
            }
        } message: {
            Text(model.t("chargeHelperInstallAuthorizationMessage"))
        }
    }

    private var intelManagedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.t("intelChargingManagedTitle"), systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
            Text(model.t("intelChargingManagedDetail"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(model.t("openBatterySettings")) { manager.openSystemBatterySettings() }
        }
    }

    @ViewBuilder
    private var systemPreferredContent: some View {
        if manager.isPreparingSoftwareMode {
            VStack(alignment: .leading, spacing: 11) {
                Text(model.t("softwareChargingPreparationTitle"))
                    .font(.subheadline.weight(.semibold))
                Text(model.t("softwareChargingPreparationIntro"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.t("softwareChargingPreparationStep1"))
                    Text(model.t("softwareChargingPreparationStep2"))
                }
                .font(.footnote)
                Text(model.t("softwareChargingPreparationReason"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(model.t("openBatterySettings")) { manager.openSystemBatterySettings() }
                    .buttonStyle(.borderedProminent)
                Toggle(
                    model.t("softwareChargingPreparationConfirmed"),
                    isOn: $manager.hasConfirmedSystemPreparation
                )
                HStack {
                    Button(model.t("cancel"), role: .cancel) { manager.cancelSoftwareModePreparation() }
                    Button(model.t("continueSoftwareCharging")) { manager.completeSoftwareModePreparation() }
                        .disabled(!manager.hasConfirmedSystemPreparation)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.t("nativeChargingAvailableTitle"))
                    .font(.subheadline.weight(.semibold))
                Text(model.t("nativeChargingAvailableDetail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(model.t("openBatterySettings")) { manager.openSystemBatterySettings() }
                    .buttonStyle(.borderedProminent)
                Divider()
                Text(model.t("preferSoftwareChargingQuestion"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(model.t("useSoftwareCharging")) { manager.beginSoftwareModePreparation() }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var eligibleControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                Text(model.t("chargeProtectionEnabled"))
                    .font(.body)
                Toggle("", isOn: Binding(
                    get: { manager.configuration.enabled },
                    set: { requestEnabledState($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.green)
                .disabled(manager.isBusy)
                if manager.isBusy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(model.t("fixedChargeLimit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if manager.isPowerUIEightyOnly {
                    Label {
                        Text(model.t("macOS158ChargeLimitNotice"))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .layoutPriority(1)
                }
                ChargeLimitPicker(manager: manager, onSelect: requestLimitSelection)
                    .disabled(manager.isBusy)
            }

            if manager.configuration.enabled && manager.configuration.fixedLimit != .oneHundred {
                HStack {
                    if manager.configuration.temporaryFullCharge {
                        Button(model.t("cancelFullCharge"), role: .cancel) {
                            manager.cancelTemporaryFullCharge()
                        }
                    } else {
                        Button(model.t("chargeToFullOnce")) {
                            manager.beginTemporaryFullCharge()
                        }
                    }
                    Spacer()
                }
                if manager.configuration.temporaryFullCharge {
                    Label(model.t("temporaryFullInProgress"), systemImage: "battery.100percent.bolt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if !manager.isInstalled {
                Text(model.t("chargeProtectionInstallNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if manager.availability == .softwareManaged {
                Text(model.t("softwareManagedReminder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(model.t("switchToSystemCharging")) {
                    manager.switchToSystemPreferred()
                }
                .buttonStyle(.link)
            }
            if manager.hasInstalledComponents && !manager.configuration.enabled {
                ChargeHelperUninstallButton(manager: manager)
            }
            if manager.status?.controlMethod == .unavailable {
                Label(model.t("chargeHelperUnavailable"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error = manager.errorMessage ?? manager.status?.lastError, !error.isEmpty {
                Label(model.t("chargeOperationFailed"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var disclosureTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var disclosureAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.88)
    }

    private func requestEnabledState(_ enabled: Bool) {
        guard enabled, manager.requiresAdministratorAuthorizationToEnable else {
            manager.setEnabled(enabled)
            return
        }
        pendingAuthorizationAction = .enable
    }

    private func requestLimitSelection(_ percentage: Int) -> Bool {
        guard manager.requiresAdministratorAuthorizationToSelectLimit(percentage) else {
            manager.selectDisplayedLimit(percentage)
            return true
        }
        pendingAuthorizationAction = .selectLimit(percentage)
        return false
    }

    private func performPendingAuthorizationAction() {
        let action = pendingAuthorizationAction
        pendingAuthorizationAction = nil
        switch action {
        case .enable:
            manager.enable()
        case .selectLimit(let percentage):
            manager.selectDisplayedLimit(percentage)
        case nil:
            break
        }
    }
}

private struct ChargeHelperUninstallButton: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var manager: ChargeProtectionManager
    @State private var showsConfirmation = false

    var body: some View {
        Button(model.t("uninstallChargeHelper"), role: .destructive) {
            showsConfirmation = true
        }
        .disabled(manager.isBusy || !manager.hasInstalledComponents)
        .help(model.t("uninstallChargeHelperDetail"))
        .accessibilityHint(model.t("uninstallChargeHelperDetail"))
        .confirmationDialog(
            model.t("uninstallChargeHelperConfirm"),
            isPresented: $showsConfirmation
        ) {
            Button(model.t("uninstallChargeHelper"), role: .destructive) {
                manager.uninstall()
            }
            Button(model.t("cancel"), role: .cancel) { }
        } message: {
            Text(
                model.t("uninstallChargeHelperDetail") + "\n\n" +
                model.t("chargeHelperUninstallAuthorizationMessage")
            )
        }
    }
}

struct ChargeLimitStatusPopoverView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var manager: ChargeProtectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                L10n.format("chargeLimitReached", model.language, manager.configuration.fixedLimit.rawValue),
                systemImage: "battery.100percent"
            )
            .font(.headline)
            if manager.configuration.fixedLimit != .oneHundred {
                if manager.configuration.temporaryFullCharge {
                    Button(model.t("cancelFullCharge"), role: .cancel) {
                        manager.cancelTemporaryFullCharge()
                    }
                } else {
                    Button(model.t("chargeToFullOnce")) {
                        manager.beginTemporaryFullCharge()
                    }
                }
            }
            Divider()
            Text(model.t("adjustFixedLimit"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ChargeLimitPicker(manager: manager)
        }
        .padding(16)
        .frame(width: 330)
    }
}

private struct DiagnosticExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date().addingTimeInterval(-3_600)
    @State private var end = Date()
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.t("diagnosticExportTitle"), systemImage: "doc.text.magnifyingglass")
                .font(.title2.weight(.semibold))
            HStack {
                quickButton("diagnosticLast15Minutes", interval: 900)
                quickButton("diagnosticLastHour", interval: 3_600)
                quickButton("diagnosticLast24Hours", interval: 86_400)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(model.t("diagnosticStartTime"))
                    DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.regular)
                        .frame(minHeight: 28, alignment: .center)
                }
                GridRow {
                    Text(model.t("diagnosticEndTime"))
                    DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.regular)
                        .frame(minHeight: 28, alignment: .center)
                }
            }
            Text(model.t("diagnosticPartialRange"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(model.t("cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.t("diagnosticExport")) { chooseDestination() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func quickButton(_ key: String, interval: TimeInterval) -> some View {
        Button(model.t(key)) {
            end = Date()
            start = end.addingTimeInterval(-interval)
            validationMessage = nil
        }
        .controlSize(.small)
    }

    private func chooseDestination() {
        let request = DiagnosticExportRequest(start: start, end: end)
        do {
            try request.validate()
        } catch DiagnosticExportValidationError.startAfterEnd {
            validationMessage = model.t("diagnosticInvalidRange")
            return
        } catch {
            validationMessage = model.t("diagnosticFutureEnd")
            return
        }
        validationMessage = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "DriveBatteryHealthViewer_Diagnostic_\(formatter.string(from: Date())).log"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try model.exportDiagnostics(request: request, to: url)
                dismiss()
            } catch {
                validationMessage = model.t("diagnosticExportFailed")
            }
        }
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
    var id: String { label }
    let label: String
    let value: String?
    let helpText: String?
    init(_ label: String, _ value: String?, helpText: String? = nil) {
        self.label = label
        self.value = value
        self.helpText = helpText
    }
}

struct DetailGrid: View {
    @EnvironmentObject private var model: AppModel
    @State private var presentedHelpID: String?
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
            HStack(spacing: 4) {
                Text(item.label)
                if let helpText = item.helpText {
                    Button {
                        presentedHelpID = item.id
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(item.label)
                    .accessibilityLabel(item.label)
                    .popover(isPresented: helpBinding(for: item.id), arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(item.label, systemImage: "clock")
                                .font(.headline)
                            Text(helpText)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(width: 380, alignment: .leading)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(item.value ?? model.t("unavailable"))
                .font(.callout)
                .foregroundStyle(item.value == nil ? Color.secondary : Color.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { presentedHelpID == id },
            set: { isPresented in
                if isPresented { presentedHelpID = id }
                else if presentedHelpID == id { presentedHelpID = nil }
            }
        )
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isSelecting = false
    @State private var showsDeleteConfirmation = false
    @State private var selectionAnchorID: UUID?

    var body: some View {
        Group {
            if model.history.isEmpty {
                EmptyState(title: model.t("historyEmpty"), detail: model.t("historyEmptyDetail"), symbol: "clock.arrow.circlepath")
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        historySelectionBar
                        Divider()
                        historyList
                    }
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)

                    if let record = model.selectedHistory {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.t("report")).font(.headline)
                                    Text(record.snapshot.generatedAt.formattedReportDate()).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !isSelecting {
                                    Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                                        Label(model.t("delete"), systemImage: "trash")
                                    }
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
                        .frame(minWidth: 280)
                    }
                }
            }
        }
        .navigationTitle(model.t("history"))
        .confirmationDialog(
            isSelecting ? model.t("deleteSelectedConfirm") : model.t("deleteConfirm"),
            isPresented: $showsDeleteConfirmation
        ) {
            if isSelecting {
                Button(model.t("deleteSelected"), role: .destructive) {
                    let ids = model.selectedHistoryIDs
                    model.deleteSelectedHistory(ids: ids)
                    isSelecting = false
                    model.clearHistorySelection()
                }
            } else {
                Button(model.t("delete"), role: .destructive) { model.deleteSelectedHistory() }
            }
            Button(model.t("cancel"), role: .cancel) { }
        } message: {
            Text(isSelecting ? model.t("deleteSelectedDetail") : model.t("deleteDetail"))
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if isSelecting {
            List(model.history) { record in
                Button {
                    selectHistoryRecord(record.id)
                } label: {
                    historyRow(record, showsSelection: true)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    model.selectedHistoryIDs.contains(record.id)
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
            }
            .listStyle(.plain)
        } else {
            List(model.history, selection: $model.selectedHistoryID) { record in
                historyRow(record, showsSelection: false)
                    .tag(record.id)
            }
        }
    }

    private func historyRow(_ record: HistoryRecord, showsSelection: Bool) -> some View {
        HStack(spacing: 10) {
            if showsSelection {
                Image(systemName: model.selectedHistoryIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.selectedHistoryIDs.contains(record.id) ? Color.accentColor : Color.secondary)
                    .imageScale(.medium)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(record.snapshot.generatedAt.formattedReportDate()).font(.headline)
                Text(record.snapshot.computerName).lineLimit(1)
                Text(model.t(record.source == .refresh ? "sourceRefresh" : "sourceExport"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var historySelectionBar: some View {
        ViewThatFits(in: .horizontal) {
            historySelectionControls(compact: false)
            historySelectionControls(compact: true)
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private func historySelectionControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            if isSelecting {
                let allSelected = model.selectedHistoryIDs.count == model.history.count
                Button {
                    if allSelected { model.clearHistorySelection() } else { model.selectAllHistory() }
                } label: {
                    if compact {
                        Image(systemName: allSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    } else {
                        Text(allSelected ? model.t("deselectAll") : model.t("selectAll"))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .help(allSelected ? model.t("deselectAll") : model.t("selectAll"))

                Spacer(minLength: compact ? 2 : 4)

                Button(action: exportSelected) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help(model.t("exportSelected"))
                .disabled(model.selectedHistoryIDs.isEmpty)

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .help(model.t("deleteSelected"))
                .disabled(model.selectedHistoryIDs.isEmpty)

                Button {
                    isSelecting = false
                    selectionAnchorID = nil
                    model.clearHistorySelection()
                } label: {
                    if compact {
                        Image(systemName: "xmark")
                    } else {
                        Text(model.t("cancel"))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .help(model.t("cancel"))
                .keyboardShortcut(.cancelAction)
            } else {
                Spacer()
                Button {
                    isSelecting = true
                    selectionAnchorID = nil
                } label: {
                    if compact {
                        Image(systemName: "checkmark.circle")
                    } else {
                        Label(model.t("select"), systemImage: "checkmark.circle")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .help(model.t("select"))
            }
        }
    }

    private func selectHistoryRecord(_ id: UUID) {
        let isExtendingRange = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift) == true
        if isExtendingRange, let anchor = selectionAnchorID {
            model.selectHistoryRange(from: anchor, through: id)
        } else {
            model.toggleHistorySelection(id)
            selectionAnchorID = id
        }
    }

    private func exportSelected() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = model.t("exportSelected")
        panel.prompt = model.t("chooseFolder")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.exportSelectedHistory(to: url)
            isSelecting = false
            model.clearHistorySelection()
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsApplicationUninstallConfirmation = false
    @State private var deletesHistoryDuringUninstall = false

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


            if model.chargeProtection.availability.permitsSoftwareControls ||
                model.chargeProtection.hasInstalledComponents {
                Section(model.t("chargeProtection")) {
                    if model.chargeProtection.availability.permitsSoftwareControls {
                        Toggle(
                            model.t("showChargeStatusInMenuBar"),
                            isOn: Binding(
                                get: { model.chargeProtection.configuration.showMenuBarStatus },
                                set: { model.chargeProtection.setMenuBarStatusVisible($0) }
                            )
                        )
                    }
                    if model.chargeProtection.hasInstalledComponents {
                        ChargeHelperUninstallButton(manager: model.chargeProtection)
                    }
                }
            }

            Section(model.t("dataAccess")) {
                Label(model.t("readOnlyNote"), systemImage: "checkmark.shield")
                Label(model.t("permissionNote"), systemImage: "externaldrive.badge.questionmark")
            }

            Section {
                Button(model.t("uninstallApplication"), role: .destructive) {
                    showsApplicationUninstallConfirmation = true
                }
                .disabled(model.chargeProtection.isBusy)
            } footer: {
                Text(model.t("uninstallApplicationDetail"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity, alignment: .top)
        .navigationTitle(model.t("settings"))
        .sheet(isPresented: $showsApplicationUninstallConfirmation) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(model.t("uninstallApplication"))
                        .font(.title2.weight(.semibold))
                }
                Text(model.t("uninstallApplicationDetail"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(model.t("deleteAllHistoryOnUninstall"), isOn: $deletesHistoryDuringUninstall)
                HStack {
                    Spacer()
                    Button(model.t("cancel"), role: .cancel) {
                        showsApplicationUninstallConfirmation = false
                    }
                    Button(model.t("uninstallApplication"), role: .destructive) {
                        model.uninstallApplication(deleteHistory: deletesHistoryDuringUninstall)
                        showsApplicationUninstallConfirmation = false
                    }
                }
            }
            .padding(24)
            .frame(width: 470)
        }
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
                    AboutButton(symbol: "sparkles", title: model.t("changelog")) { model.showsChangelog = true }
                    Divider().padding(.leading, 46)
                    AboutButton(symbol: "arrow.clockwise", title: model.t("checkForUpdates")) { model.checkForUpdates() }
                        .disabled(model.isCheckingForUpdates)
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
                .dbhvCardSurface(cornerRadius: 12)
                .frame(maxWidth: 620)

                Text(model.t("readOnlyNote")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(model.t("copyright")).font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t("about"))
        .sheet(isPresented: $model.showsChangelog) {
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
                            ForEach(release.sections) { section in
                                if release.sections.count > 1 {
                                    Text(section.kind.title(for: model.language))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                }
                                ForEach(section.items, id: \.self) { item in
                                    Label(item, systemImage: section.kind.symbol)
                                        .foregroundStyle(.primary, section.kind.color)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if release.id != releases.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)
                .textSelection(.enabled)
            }
        }
        .padding(28)
        .frame(width: 650, height: 560)
    }
}

struct ChangelogRelease: Identifiable {
    var id: String { version }
    let version: String
    let sections: [ChangelogSection]

    static func localized(for language: AppLanguage) -> [ChangelogRelease] {
        switch L10n.effective(language) {
        case .simplifiedChinese:
            return releases(
                currentFeatures: [
                    "在 macOS 15.8 上新增 PowerUI 原生 80% 充电上限，仅开放系统实际支持的档位，并保持适配器供电。",
                    "为 iMac、Mac mini、Mac Studio 等桌面设备的“电池”部分设计了新的界面显示。"
                ],
                currentFixes: [],
                majorFeatures: [
                    "新增 Apple Silicon Mac 电池充电保护，支持 80% 至 100% 固定充电上限、“本次充满”以及启用保护期间持续可用的菜单栏状态与快捷控制。",
                    "新增可按时间范围导出的隐私友好诊断日志。",
                    "新增概览中的非正常关机次数与错误日志条目显示。",
                    "新增版本更新后的非打扰式更新日志提示。",
                    "新增“关于”页面中的检查更新入口，便于用户发现并使用更新功能。"
                ],
                majorImprovements: ["优化了概览中保存（导出）报告按钮的图标样式，使功能含义更加直观。", "优化了历史记录选择界面的按钮布局与多选操作体验。", "为内置 SSD 的“工作时间”增加说明，便于理解固件统计值与 Mac 实际使用时间的差异。"],
                latestFeatures: [
                    "增强外接存储设备的信息识别与只读检测兼容性。"
                ],
                latestFixes: [
                    "修复了外接硬盘热插拔、设备身份或 S.M.A.R.T. 字段匹配异常时，可能显示错误或旧数据的问题。",
                    "修复了硬件查询无响应、读取被取消或重复刷新时，界面可能停滞、更新旧结果或丢失 NVMe 数据的问题。"
                ],
                patchFeatures: [
                    "增强外接 USB、Thunderbolt 以及支持 SAT 透传的硬盘详细信息读取能力。"
                ],
                patchFixes: [
                    "修复了关闭主窗口后从程序坞重新打开应用时可能意外退出的问题。",
                    "修复了睡眠唤醒或存储控制器重置后，NVMe 实时读取可能继续使用失效接口的问题。",
                    "修复了首次启动并跟随系统语言时，顶部应用菜单名称可能显示为英文的问题。"
                ],
                features: [
                    "新增历史记录多选、全选、批量导出和批量删除功能。",
                    "新增对 macOS 26 及以上版本 Liquid Glass 界面效果的支持。",
                    "新增检查更新功能。"
                ],
                fixes: [
                    "修复了顶部系统菜单可能卡住、残留或重复显示窗口项目的问题。",
                    "修复了切换应用语言后，顶部菜单及其子菜单语言未能同步更新的问题。"
                ],
                previous: [
                    "修复重复刷新后 NVMe S.M.A.R.T. 数据消失的问题。",
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
                currentFeatures: ["В macOS 15.8 добавлен системный предел PowerUI 80% с сохранением питания от адаптера; доступны только реально поддерживаемые системой уровни.", "Для раздела «Батарея» на настольных Mac, включая iMac, Mac mini и Mac Studio, создано новое оформление."],
                currentFixes: [],
                majorFeatures: ["Добавлена защита зарядки Apple Silicon Mac с фиксированными пределами от 80% до 100%, разовой полной зарядкой и быстрым управлением из строки меню при достижении заданного уровня.", "Добавлены конфиденциальные диагностические журналы с экспортом за выбранный период.", "В обзор накопителей добавлены значения небезопасных выключений и записей журнала ошибок.", "Добавлена ненавязчивая подсказка о журнале изменений после обновления приложения.", "На страницу «О программе» добавлена команда проверки обновлений, чтобы её было проще найти и использовать."],
                majorImprovements: ["Улучшен значок сохранения (экспорта) отчёта в обзоре, чтобы назначение функции было понятнее.", "Улучшены кнопки и выбор диапазона в режиме выбора записей истории.", "Для «Времени работы» встроенного SSD добавлено пояснение отличия от фактического времени использования Mac."],
                latestFeatures: ["Улучшены распознавание информации и совместимость диагностики внешних накопителей в режиме только для чтения."],
                latestFixes: ["Исправлена проблема, из-за которой при горячем подключении, ошибках идентификации устройства или сопоставления полей S.M.A.R.T. могли отображаться неверные либо устаревшие данные.", "Исправлена проблема, из-за которой при отсутствии ответа оборудования, отмене чтения или повторном обновлении интерфейс мог зависнуть, применить устаревший результат либо потерять данные NVMe."],
                patchFeatures: ["Расширено чтение подробных данных внешних дисков USB, Thunderbolt и устройств с поддержкой SAT passthrough."],
                patchFixes: ["Исправлена проблема, из-за которой приложение могло аварийно завершиться при повторном открытии из Dock после закрытия главного окна.", "Исправлена проблема, из-за которой после сна, пробуждения или сброса контроллера чтение NVMe могло использовать недействительный интерфейс.", "Исправлена проблема, из-за которой при первом запуске с системным языком название меню приложения могло отображаться на английском."],
                features: ["Добавлены множественный выбор, выбор всех записей, пакетный экспорт и пакетное удаление истории.", "Добавлена поддержка интерфейсного эффекта Liquid Glass в macOS 26 и более новых версиях.", "Добавлена проверка обновлений."],
                fixes: ["Исправлена проблема, из-за которой верхнее системное меню могло зависать, оставаться на экране или дублировать команды окна.", "Исправлена проблема, из-за которой верхнее меню и его подменю не меняли язык вместе с приложением."],
                previous: ["Исправлено исчезновение данных NVMe S.M.A.R.T. после повторного обновления.", "Заряд, состояние зарядки, питание и температуры диска и батареи обновляются автоматически.", "Поля диска и батареи упорядочены; ёмкость показывается в mAh / Wh.", "Размер значка приведён к стандартам macOS."],
                initial: ["Нативный интерфейс SwiftUI с тёмным режимом и функциями доступности.", "Диагностика диска и батареи только для чтения, история и экспорт отчётов.", "Поддержка Intel и Apple silicon в Universal 2.", "Семь языков, защита серийных номеров и настройка текста отчёта."]
            )
        case .french:
            return releases(
                currentFeatures: ["Ajout de la limite native PowerUI de 80 % sous macOS 15.8, tout en conservant l’alimentation par l’adaptateur et en ne proposant que le niveau réellement pris en charge.", "Nouvelle présentation de la section Batterie pour les Mac de bureau tels que l’iMac, le Mac mini et le Mac Studio."],
                currentFixes: [],
                majorFeatures: ["Ajout de la protection de charge des Mac Apple Silicon avec des limites fixes de 80 % à 100 %, une charge complète temporaire et des commandes rapides dans la barre des menus lorsque le niveau défini est atteint.", "Ajout de journaux de diagnostic respectueux de la vie privée, exportables par période.", "Ajout des arrêts non sécurisés et des entrées du journal d’erreurs dans l’aperçu des disques.", "Ajout d’une invite discrète vers les notes de version après les mises à jour.", "Ajout de la recherche de mises à jour dans la page À propos afin de rendre cette fonction plus facile à trouver et à utiliser."],
                majorImprovements: ["Amélioration de l’icône d’enregistrement (exportation) des rapports dans l’aperçu afin de mieux exprimer sa fonction.", "Amélioration des boutons et de la sélection par plage dans l’interface de sélection de l’historique.", "Ajout d’une explication au temps de fonctionnement du SSD interne afin de distinguer le comptage du micrologiciel du temps d’utilisation réel du Mac."],
                latestFeatures: ["Amélioration de l’identification des informations et de la compatibilité du diagnostic en lecture seule des stockages externes."],
                latestFixes: ["Correction d’un problème pouvant afficher des données erronées ou obsolètes après un branchement à chaud, une erreur d’identification du périphérique ou d’association des champs S.M.A.R.T.", "Correction d’un problème où une requête matérielle sans réponse, une lecture annulée ou des actualisations répétées pouvaient bloquer l’interface, appliquer un ancien résultat ou faire disparaître les données NVMe."],
                patchFeatures: ["Amélioration de la lecture des informations détaillées des disques externes USB, Thunderbolt et compatibles avec le relais SAT."],
                patchFixes: ["Correction d’un problème pouvant fermer inopinément l’app lors de sa réouverture depuis le Dock après la fermeture de la fenêtre principale.", "Correction d’un problème pouvant réutiliser une interface NVMe devenue invalide après la veille, le réveil ou la réinitialisation du contrôleur.", "Correction d’un problème pouvant afficher en anglais le nom du menu de l’app au premier lancement avec la langue système."],
                features: ["Ajout de la sélection multiple, de Tout sélectionner, de l’export groupé et de la suppression groupée dans l’historique.", "Ajout de la prise en charge de l’effet d’interface Liquid Glass sous macOS 26 et versions ultérieures.", "Ajout de la recherche de mises à jour."],
                fixes: ["Correction d’un problème pouvant bloquer ou laisser affiché le menu système supérieur, ou dupliquer les commandes de fenêtre.", "Correction d’un problème empêchant le menu supérieur et ses sous-menus de suivre la langue choisie dans l’app."],
                previous: ["Correction de la disparition des données NVMe S.M.A.R.T. après plusieurs actualisations.", "Le niveau de batterie, la charge, l’alimentation et les températures du disque et de la batterie se mettent à jour automatiquement.", "Ordre des champs harmonisé et capacités affichées en mAh / Wh.", "Taille de l’icône alignée sur les conventions macOS."],
                initial: ["Interface SwiftUI native avec mode sombre et accessibilité.", "Lecture seule des disques et de la batterie, historique et export des rapports.", "Compatibilité Intel et Apple silicon avec Universal 2.", "Sept langues, confidentialité des numéros de série et taille de rapport réglable."]
            )
        case .german:
            return releases(
                currentFeatures: ["Unter macOS 15.8 wurde die native PowerUI-Ladegrenze von 80 % ergänzt; das Netzteil bleibt verbunden und nur tatsächlich unterstützte Stufen sind auswählbar.", "Der Bereich „Batterie“ wurde für Desktop-Macs wie iMac, Mac mini und Mac Studio neu gestaltet."],
                currentFixes: [],
                majorFeatures: ["Batterieladeschutz für Apple-Silicon-Macs mit festen Grenzen von 80 % bis 100 %, einmaligem vollständigem Laden und Schnellsteuerung über die Menüleiste beim Erreichen des festgelegten Ladestands hinzugefügt.", "Datenschutzfreundliche Diagnoseprotokolle mit Zeitraumexport hinzugefügt.", "Unsichere Abschaltungen und Fehlerprotokolleinträge wurden zur Laufwerksübersicht hinzugefügt.", "Ein dezenter Hinweis auf die Versionshinweise nach App-Updates wurde hinzugefügt.", "Die Update-Suche wurde zur Info-Seite hinzugefügt, damit sie leichter zu finden und zu verwenden ist."],
                majorImprovements: ["Das Symbol zum Speichern (Exportieren) von Berichten in der Übersicht wurde verständlicher gestaltet.", "Schaltflächen und Bereichsauswahl in der Verlaufsauswahl wurden verbessert.", "Für die Betriebszeit der internen SSD wurde eine Erläuterung zum Unterschied zwischen Firmware-Zählung und tatsächlicher Mac-Nutzungszeit ergänzt."],
                latestFeatures: ["Die Informationserkennung und die Kompatibilität der schreibgeschützten Prüfung externer Speicher wurden verbessert."],
                latestFixes: ["Ein Problem wurde behoben, durch das bei Hot-Plug-Vorgängen sowie Fehlern bei Geräteidentität oder S.M.A.R.T.-Feldzuordnung falsche oder veraltete Daten angezeigt werden konnten.", "Ein Problem wurde behoben, durch das nicht antwortende Hardwareabfragen, abgebrochene Lesevorgänge oder wiederholte Aktualisierungen die Oberfläche blockieren, alte Ergebnisse anwenden oder NVMe-Daten ausblenden konnten."],
                patchFeatures: ["Das Auslesen detaillierter Informationen externer USB-, Thunderbolt- und SAT-Passthrough-Laufwerke wurde erweitert."],
                patchFixes: ["Ein Problem wurde behoben, durch das die App beim erneuten Öffnen aus dem Dock nach dem Schließen des Hauptfensters unerwartet beendet werden konnte.", "Ein Problem wurde behoben, durch das die NVMe-Abfrage nach Ruhezustand, Aufwachen oder Controller-Reset eine ungültige Schnittstelle weiterverwenden konnte.", "Ein Problem wurde behoben, durch das der Name des App-Menüs beim ersten Start mit Systemsprache auf Englisch erscheinen konnte."],
                features: ["Mehrfachauswahl, Alle auswählen, Sammelexport und Sammellöschen für Verlaufseinträge hinzugefügt.", "Unterstützung für den Liquid-Glass-Oberflächeneffekt ab macOS 26 hinzugefügt.", "Eine Funktion zur Suche nach Updates wurde hinzugefügt."],
                fixes: ["Ein Problem wurde behoben, durch das das obere Systemmenü hängen bleiben, sichtbar bleiben oder Fensterbefehle doppelt anzeigen konnte.", "Ein Problem wurde behoben, durch das das obere Menü und seine Untermenüs der in der App gewählten Sprache nicht folgten."],
                previous: ["Behoben: NVMe-S.M.A.R.T.-Daten verschwanden nach erneutem Aktualisieren.", "Akkustand, Ladezustand, Netzanschluss sowie Laufwerks- und Akkutemperatur werden automatisch aktualisiert.", "Feldreihenfolge vereinheitlicht und Kapazitäten als mAh / Wh dargestellt.", "Symbolgröße an macOS-Konventionen angepasst."],
                initial: ["Native SwiftUI-Oberfläche mit Dunkelmodus und Bedienungshilfen.", "Nur-Lese-Prüfung von Laufwerk und Akku, Verlauf und Berichtsexport.", "Universal-2-Unterstützung für Intel und Apple Chips.", "Sieben Sprachen, Schutz der Seriennummern und anpassbare Berichtsschrift."]
            )
        case .korean:
            return releases(
                currentFeatures: ["macOS 15.8에서 어댑터 전원을 유지하는 PowerUI 기본 80% 충전 한도를 추가하고 실제 지원되는 단계만 선택할 수 있게 했습니다.", "iMac, Mac mini, Mac Studio 등 데스크톱 Mac의 ‘배터리’ 영역을 위한 새로운 UI를 추가했습니다."],
                currentFixes: [],
                majorFeatures: ["Apple Silicon Mac에 80%~100% 고정 충전 한도, 이번에 완전히 충전, 설정 전력 도달 시 메뉴 막대 빠른 제어를 지원하는 배터리 충전 보호를 추가했습니다.", "선택한 기간을 내보낼 수 있는 개인정보 보호 진단 로그를 추가했습니다.", "드라이브 개요에 비정상 종료 횟수와 오류 로그 항목을 추가했습니다.", "앱 업데이트 후 업데이트 기록을 안내하는 간결한 팁을 추가했습니다.", "업데이트 기능을 더 쉽게 찾고 사용할 수 있도록 정보 화면에 업데이트 확인 항목을 추가했습니다."],
                majorImprovements: ["개요의 보고서 저장(내보내기) 아이콘을 기능이 더 명확하게 보이도록 개선했습니다.", "기록 선택 화면의 버튼과 범위 선택 조작을 개선했습니다.", "내장 SSD의 사용 시간에 펌웨어 집계값과 Mac의 실제 사용 시간의 차이를 설명하는 안내를 추가했습니다."],
                latestFeatures: ["외장 저장 장치의 정보 식별과 읽기 전용 검사 호환성을 개선했습니다."],
                latestFixes: ["핫 플러그, 장치 식별 또는 S.M.A.R.T. 필드 연결 오류로 잘못되거나 오래된 데이터가 표시될 수 있는 문제를 수정했습니다.", "하드웨어 조회 무응답, 읽기 취소 또는 반복 새로 고침 시 화면이 멈추거나 이전 결과가 반영되거나 NVMe 데이터가 사라질 수 있는 문제를 수정했습니다."],
                patchFeatures: ["외장 USB·Thunderbolt 드라이브와 SAT 패스스루 지원 드라이브의 상세 정보 읽기 기능을 강화했습니다."],
                patchFixes: ["기본 창을 닫은 뒤 Dock에서 앱을 다시 열 때 예기치 않게 종료될 수 있는 문제를 수정했습니다.", "잠자기·깨우기 또는 저장 장치 컨트롤러 재설정 후 NVMe 실시간 읽기가 무효화된 인터페이스를 계속 사용할 수 있는 문제를 수정했습니다.", "시스템 언어를 따르는 첫 실행에서 앱 메뉴 이름이 영어로 표시될 수 있는 문제를 수정했습니다."],
                features: ["기록 다중 선택, 모두 선택, 일괄 내보내기 및 일괄 삭제 기능을 추가했습니다.", "macOS 26 이상에서 Liquid Glass 인터페이스 효과 지원을 추가했습니다.", "업데이트 확인 기능을 추가했습니다."],
                fixes: ["상단 시스템 메뉴가 멈추거나 화면에 남거나 윈도우 항목을 중복 표시할 수 있는 문제를 수정했습니다.", "앱에서 선택한 언어에 맞춰 상단 메뉴와 하위 메뉴의 언어가 변경되지 않는 문제를 수정했습니다."],
                previous: ["반복 새로 고침 후 NVMe S.M.A.R.T. 데이터가 사라지는 문제를 수정했습니다.", "배터리 잔량, 충전 상태, 전원 연결 상태와 드라이브·배터리 온도가 자동으로 갱신됩니다.", "드라이브와 배터리 필드 순서를 통일하고 용량을 mAh / Wh로 표시합니다.", "앱 아이콘 크기를 macOS 규칙에 맞췄습니다."],
                initial: ["다크 모드와 손쉬운 사용을 지원하는 네이티브 SwiftUI 인터페이스.", "읽기 전용 드라이브·배터리 검사, 기록 및 보고서 내보내기.", "Intel 및 Apple 칩을 위한 Universal 2 지원.", "7개 언어, 일련번호 보호 및 보고서 글자 크기 조절."]
            )
        case .japanese:
            return releases(
                currentFeatures: ["macOS 15.8 で、電源アダプタ接続を維持する PowerUI ネイティブ 80% 上限を追加し、実際に対応する段階のみ選択可能にしました。", "iMac、Mac mini、Mac Studio などのデスクトップ Mac 向けに、「バッテリー」セクションの新しい表示を追加しました。"],
                currentFixes: [],
                majorFeatures: ["Apple Silicon Mac に、80%～100% の固定充電上限、今回だけ満充電、設定した残量に達したときのメニューバーからのクイック操作を備えた充電保護を追加しました。", "期間を指定して書き出せるプライバシー配慮型の診断ログを追加しました。", "ドライブの概要に、安全でないシャットダウン回数とエラーログエントリを追加しました。", "アプリ更新後に更新履歴を案内する控えめなヒントを追加しました。", "アップデート機能を見つけて使いやすくするため、このアプリについて画面にアップデート確認を追加しました。"],
                majorImprovements: ["概要のレポート保存（書き出し）アイコンを、機能がより明確に伝わるよう改善しました。", "履歴選択画面のボタンと範囲選択の操作性を改善しました。", "内蔵 SSD の「使用時間」に、ファームウェアの集計値と Mac の実際の使用時間の違いを示す説明を追加しました。"],
                latestFeatures: ["外付けストレージの情報識別と読み取り専用検査の互換性を改善しました。"],
                latestFixes: ["ホットプラグ、デバイス識別、または S.M.A.R.T. フィールドの対応に問題がある場合、誤ったデータや古いデータが表示されることがある問題を修正しました。", "ハードウェア照会の無応答、読み取りのキャンセル、または再更新時に、画面が停止する、古い結果が反映される、または NVMe データが消えることがある問題を修正しました。"],
                patchFeatures: ["外付け USB・Thunderbolt ドライブおよび SAT パススルー対応ドライブの詳細情報取得を強化しました。"],
                patchFixes: ["メインウインドウを閉じた後、Dock からアプリを再度開くと予期せず終了することがある問題を修正しました。", "スリープ、復帰、またはストレージコントローラのリセット後に、NVMe のリアルタイム読み取りが無効なインターフェイスを再利用することがある問題を修正しました。", "初回起動時にシステム言語を使用すると、アプリメニュー名が英語で表示されることがある問題を修正しました。"],
                features: ["履歴の複数選択、すべて選択、一括書き出し、一括削除を追加しました。", "macOS 26 以降の Liquid Glass インターフェイス効果に対応しました。", "アップデート確認機能を追加しました。"],
                fixes: ["上部のシステムメニューが固まる、残る、またはウインドウ項目が重複することがある問題を修正しました。", "アプリで選択した言語に上部メニューとサブメニューの言語が連動しない問題を修正しました。"],
                previous: ["再更新後に NVMe S.M.A.R.T. データが消える問題を修正しました。", "バッテリー残量、充電状態、電源接続状態、ドライブとバッテリーの温度を自動更新します。", "ドライブとバッテリーの項目順を統一し、容量を mAh / Wh で表示します。", "アプリアイコンのサイズを macOS の慣例に合わせました。"],
                initial: ["ダークモードとアクセシビリティに対応したネイティブ SwiftUI UI。", "読み取り専用のドライブ・バッテリー検査、履歴、レポート書き出し。", "Intel と Apple チップに対応する Universal 2。", "7 言語、シリアル番号保護、レポート文字サイズ調整に対応。"]
            )
        case .english, .system:
            return releases(
                currentFeatures: ["Added the native PowerUI 80% limit on macOS 15.8 while keeping adapter power available and allowing only the level the system can enforce.", "Added a new Battery-section design for desktop Macs such as iMac, Mac mini, and Mac Studio."],
                currentFixes: [],
                majorFeatures: ["Added Apple Silicon Mac charge protection with fixed limits from 80% to 100%, a one-time full-charge override, and quick menu-bar controls when the set level is reached.", "Added privacy-friendly diagnostic logs with time-range export.", "Added unsafe-shutdown and error-log-entry values to the drive overview.", "Added a quiet release-notes prompt after app updates.", "Added a Check for Updates entry to the About page so the update feature is easier to find and use."],
                majorImprovements: ["Improved the icon for saving (exporting) reports in Overview so its purpose is clearer.", "Improved button sizing and range selection in the history selection interface.", "Added an explanation for internal SSD operating time to clarify the difference between firmware accounting and the Mac’s actual usage time."],
                latestFeatures: ["Improved information identification and read-only diagnostic compatibility for external storage."],
                latestFixes: ["Fixed an issue where hot-plugging or mismatched device identity or S.M.A.R.T. fields could display incorrect or stale data.", "Fixed an issue where unresponsive hardware queries, canceled reads, or repeated refreshes could stall the interface, apply stale results, or hide NVMe data."],
                patchFeatures: ["Expanded detailed information reading for external USB and Thunderbolt drives and drives with SAT pass-through support."],
                patchFixes: ["Fixed an issue where the app could quit unexpectedly when reopened from the Dock after closing the main window.", "Fixed an issue where NVMe live reading could reuse an invalid interface after sleep, wake, or a storage-controller reset.", "Fixed an issue where the application menu name could appear in English on first launch while following the system language."],
                features: ["Added multi-selection, Select All, batch export, and batch deletion for history records.", "Added support for Liquid Glass interface effects on macOS 26 and later.", "Added update checking."],
                fixes: ["Fixed an issue where the top system menu could become stuck, remain visible, or duplicate Window commands.", "Fixed an issue where the top menu and its submenus did not follow the language selected in the app."],
                previous: ["Fixed NVMe S.M.A.R.T. values disappearing after repeated refreshes.", "Battery level, charging state, power connection, and drive and battery temperatures now update automatically.", "Aligned drive and battery field order and display capacities as mAh / Wh.", "Adjusted the app icon safe area."],
                initial: ["Native SwiftUI interface with Dark Mode and accessibility support.", "Read-only drive and battery scans, history, report copy, and export.", "Universal 2 support for Intel and Apple silicon Macs.", "Seven languages, serial-number privacy, and adjustable report text."]
            )
        }
    }

    private static func releases(
        currentFeatures: [String],
        currentFixes: [String],
        majorFeatures: [String],
        majorImprovements: [String],
        latestFeatures: [String],
        latestFixes: [String],
        patchFeatures: [String],
        patchFixes: [String],
        features: [String],
        fixes: [String],
        previous: [String],
        initial: [String]
    ) -> [ChangelogRelease] {
        let previousFeatures = previous.indices.contains(2) ? [previous[1], previous[2]] : []
        let previousFixes = previous.indices.contains(3) ? [previous[0], previous[3]] : previous
        let headlineFeatures = majorFeatures.first.map { [$0] } ?? []
        let remainingMajorFeatures = Array(majorFeatures.dropFirst())
        var currentSections = [
            ChangelogSection(
                kind: .feature,
                items: headlineFeatures + currentFeatures + remainingMajorFeatures
            ),
            ChangelogSection(kind: .improvement, items: majorImprovements)
        ]
        if !currentFixes.isEmpty {
            currentSections.append(ChangelogSection(kind: .fix, items: currentFixes))
        }
        return [
            ChangelogRelease(version: "1.1.0", sections: currentSections),
            ChangelogRelease(version: "1.0.6", sections: [
                ChangelogSection(kind: .feature, items: patchFeatures + latestFeatures),
                ChangelogSection(kind: .fix, items: patchFixes + latestFixes)
            ]),
            ChangelogRelease(version: "1.0.5", sections: [
                ChangelogSection(kind: .feature, items: features),
                ChangelogSection(kind: .fix, items: fixes)
            ]),
            ChangelogRelease(version: "1.0.4", sections: [
                ChangelogSection(kind: .feature, items: previousFeatures),
                ChangelogSection(kind: .fix, items: previousFixes)
            ]),
            ChangelogRelease(version: "1.0.0", sections: [ChangelogSection(kind: .historical, items: initial)])
        ]
    }
}

struct ChangelogSection: Identifiable {
    var id: ChangelogItemKind { kind }
    let kind: ChangelogItemKind
    let items: [String]
}

enum ChangelogItemKind: String, Identifiable {
    var id: String { rawValue }
    case feature
    case improvement
    case fix
    case historical

    var symbol: String {
        switch self {
        case .feature: return "checkmark.circle.fill"
        case .improvement: return "wand.and.stars"
        case .fix: return "wrench.and.screwdriver.fill"
        case .historical: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .feature: return .green
        case .improvement: return .blue
        case .fix: return .orange
        case .historical: return .green
        }
    }

    func title(for language: AppLanguage) -> String {
        switch (self, L10n.effective(language)) {
        case (.feature, .simplifiedChinese): return "新增功能"
        case (.improvement, .simplifiedChinese): return "优化改进"
        case (.fix, .simplifiedChinese): return "问题修复"
        case (.feature, .russian): return "Новые функции"
        case (.improvement, .russian): return "Улучшения"
        case (.fix, .russian): return "Исправления"
        case (.feature, .french): return "Nouveautés"
        case (.improvement, .french): return "Améliorations"
        case (.fix, .french): return "Correctifs"
        case (.feature, .german): return "Neue Funktionen"
        case (.improvement, .german): return "Verbesserungen"
        case (.fix, .german): return "Fehlerbehebungen"
        case (.feature, .korean): return "새로운 기능"
        case (.improvement, .korean): return "개선 사항"
        case (.fix, .korean): return "문제 수정"
        case (.feature, .japanese): return "新機能"
        case (.improvement, .japanese): return "改善"
        case (.fix, .japanese): return "修正"
        case (.feature, .english), (.feature, .system): return "New Features"
        case (.improvement, .english), (.improvement, .system): return "Improvements"
        case (.fix, .english), (.fix, .system): return "Fixes"
        case (.historical, _): return ""
        }
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

struct DesktopMacEmptyCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("desktopMacEmptyStateAnimationShown") private var hasShownAnimation = false
    @State private var highlightsPower = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(5)
                    .background(.background, in: Circle())
                    .offset(x: 7, y: highlightsPower ? 3 : 7)
                    .scaleEffect(highlightsPower ? 1.08 : 1)
            }
            .frame(width: 62, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Label(model.t("desktopMacMode"), systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.11), in: Capsule())
                Text(model.t("desktopMacPoweredTitle"))
                    .font(.headline)
                Text(model.t("noBattery"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.t("desktopMacPoweredDetail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.t("desktopMacMode")). \(model.t("desktopMacPoweredTitle")). " +
            "\(model.t("noBattery")) \(model.t("desktopMacPoweredDetail"))"
        )
        .onAppear(perform: playAnimationOnce)
    }

    private func playAnimationOnce() {
        guard !hasShownAnimation else { return }
        hasShownAnimation = true
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
            highlightsPower = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeOut(duration: 0.22)) {
                highlightsPower = false
            }
        }
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
            .dbhvCardSurface(cornerRadius: 13)
    }

    /// macOS 13–15 keeps the existing opaque card treatment. Builds made with
    /// the macOS 26 SDK use native Liquid Glass on newer systems; older SDKs
    /// retain a compatible system-material treatment without private APIs.
    @ViewBuilder
    func dbhvCardSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(.white.opacity(0.24), lineWidth: 0.65))
                .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
        } else {
            self
                .background(.background, in: shape)
                .overlay(shape.stroke(Color.secondary.opacity(0.16)))
                .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        }
#else
        if #available(macOS 26.0, *) {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.fill(.white.opacity(0.06)))
                .overlay(shape.stroke(.white.opacity(0.28), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
        } else {
            self
                .background(.background, in: shape)
                .overlay(shape.stroke(Color.secondary.opacity(0.16)))
                .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        }
#endif
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
