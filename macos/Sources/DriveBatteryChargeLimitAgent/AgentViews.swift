import AppKit
import SwiftUI

struct ChargeLimitAgentPopoverView: View {
    @ObservedObject var model: ChargeLimitAgentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                model.statusItemLabel,
                systemImage: presentationSystemImage
            )
            .font(.headline)
            HStack(spacing: 12) {
                if model.configuration.fixedLimit != .oneHundred {
                    Button(
                        AgentL10n.text(
                            model.configuration.temporaryFullCharge ? "cancelFull" : "full",
                            language: model.language
                        )
                    ) {
                        model.toggleTemporaryFullCharge()
                    }
                }
                Toggle(
                    AgentL10n.text("menuBar", language: model.language),
                    isOn: Binding(
                        get: { model.configuration.showMenuBarStatus },
                        set: { model.setMenuBarStatusVisible($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
            Divider()
            Text(AgentL10n.text("adjust", language: model.language))
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.isPowerUIEightyOnly {
                Label(AgentL10n.text("only80", language: model.language), systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            AgentChargeLimitPicker(model: model)
        }
        .padding(16)
        .frame(width: 330)
    }

    private var presentationSystemImage: String {
        switch model.presentationState {
        case .protectionActive: return "battery.75percent"
        case .limitReached: return "battery.100percent"
        case .temporaryFullCharge: return "bolt.fill"
        case .attentionRequired: return "exclamationmark.triangle.fill"
        }
    }
}

private struct AgentChargeLimitPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: ChargeLimitAgentModel
    @State private var draggingValue: Double?
    @State private var presentedIndex: Double?

    private let percentages = [80, 85, 90, 95, 100]
    var body: some View {
        standardPicker
        .onAppear {
            if presentedIndex == nil { presentedIndex = Double(selectedIndex) }
        }
        .onChange(of: model.displayedLimitPercentage) { _ in
            guard draggingValue == nil else { return }
            let target = Double(selectedIndex)
            guard presentedIndex != target else { return }
            if presentedIndex == nil { presentedIndex = target }
            else { withAnimation(selectionAnimation) { presentedIndex = target } }
        }
    }

    private var standardPicker: some View {
        VStack(spacing: 6) {
            track
            HStack(spacing: 0) {
                ForEach(Array(percentages.enumerated()), id: \.offset) { index, percentage in
                    Button { settle(on: index) } label: {
                        optionLabel(percentage)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isLimitSelectable(percentage))
                    .help("\(percentage)%")
                    .opacity(model.isLimitSelectable(percentage) ? 1 : 0.38)
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
            }
            .frame(height: 38)
        }
    }

    private func optionLabel(_ percentage: Int) -> some View {
        VStack(spacing: 2) {
            AgentBatteryIcon(percent: percentage)
            Text("\(percentage)%").font(.caption2.monospacedDigit())
        }
        .foregroundStyle(isSelected(percentage) ? Color.accentColor : Color.secondary)
        .fontWeight(isSelected(percentage) ? .semibold : .regular)
        .frame(maxWidth: .infinity, minHeight: 34)
    }

    private var selectedIndex: Int {
        percentages.firstIndex(of: model.displayedLimitPercentage) ?? percentages.count - 1
    }

    private var displayedValue: Double {
        draggingValue ?? presentedIndex ?? Double(selectedIndex)
    }

    private var displayedIndex: Int {
        min(percentages.count - 1, max(0, Int(displayedValue.rounded())))
    }

    private var track: some View {
        GeometryReader { geometry in
            let trackInset = trackInset(for: geometry.size.width)
            let trackWidth = max(0, geometry.size.width - trackInset * 2)
            let thumbX = trackInset + trackWidth * CGFloat(displayedValue) /
                CGFloat(percentages.count - 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .separatorColor)).frame(height: 4)
                    .padding(.horizontal, trackInset)
                Capsule().fill(Color.accentColor.opacity(0.72))
                    .frame(width: max(0, thumbX - trackInset), height: 4)
                    .offset(x: trackInset)
                ForEach(percentages.indices, id: \.self) { index in
                    let isSelectable = model.isLimitSelectable(percentages[index])
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
                Circle().fill(.background).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.5)
                    .position(x: thumbX, y: 11)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(geometry.size.width - trackInset,
                                    max(trackInset, gesture.location.x))
                        let value = Double((x - trackInset) / max(1, trackWidth)) *
                            Double(percentages.count - 1)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { draggingValue = value }
                    }
                    .onEnded { gesture in
                        let x = min(geometry.size.width - trackInset,
                                    max(trackInset, gesture.location.x))
                        let value = Double((x - trackInset) / max(1, trackWidth)) *
                            Double(percentages.count - 1)
                        settle(on: Int(value.rounded()))
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentL10n.text("fixed", language: model.language))
        .accessibilityValue("\(percentages[displayedIndex])%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settle(on: nextSelectableIndex(after: displayedIndex))
            case .decrement: settle(on: previousSelectableIndex(before: displayedIndex))
            @unknown default: break
            }
        }
    }

    private func settle(on index: Int) {
        guard percentages.indices.contains(index),
              model.isLimitSelectable(percentages[index]) else {
            withAnimation(selectionAnimation) {
                draggingValue = nil
                presentedIndex = Double(selectedIndex)
            }
            return
        }
        withAnimation(selectionAnimation) {
            draggingValue = nil
            presentedIndex = Double(index)
        }
        model.selectDisplayedLimit(percentages[index])
    }

    private func nextSelectableIndex(after index: Int) -> Int {
        percentages.indices.first {
            $0 > index && model.isLimitSelectable(percentages[$0])
        } ?? index
    }

    private func previousSelectableIndex(before index: Int) -> Int {
        percentages.indices.reversed().first {
            $0 < index && model.isLimitSelectable(percentages[$0])
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

private struct AgentBatteryIcon: View {
    let percent: Int

    private var fraction: CGFloat { CGFloat(percent) / 100 }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .stroke(lineWidth: 1.5)
                .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .frame(width: max(2, 18 * fraction), height: 7)
                .offset(x: 2)
            Capsule().frame(width: 2, height: 5).offset(x: 23)
        }
        .frame(width: 25, height: 14)
        .accessibilityHidden(true)
    }
}
