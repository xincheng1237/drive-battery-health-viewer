import AppKit
import Combine
import OSLog
import SwiftUI

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class ChargeLimitAgentStatusItemController: NSObject, NSPopoverDelegate {
    /// Versioned once to discard the old manually seeded position. AppKit owns
    /// both placement and visibility persistence for this identifier.
    static let statusItemAutosaveName =
        "com.chengxin.drivebatteryhealthviewer.charge-protection-v2"
    static let legacyStatusItemAutosaveName =
        "com.chengxin.drivebatteryhealthviewer.charge-limit-reached"
    static let preferredPositionDefaultsKey =
        "NSStatusItem Preferred Position \(statusItemAutosaveName)"
    static let rememberedPreferredPositionDefaultsKey =
        "DBHV Remembered StatusItem Preferred Position \(statusItemAutosaveName)"
    static let fallbackPreferredPosition: Double = 350
    static let recoveryInterval: TimeInterval = 2
    static let visibilityTransitionDelay: TimeInterval = 3
    static let fadeDuration: TimeInterval = 0.28
    static let fadeFrameCount = 12
    static let buttonAvailabilityRetryLimit = 20

    private let model: ChargeLimitAgentModel
    private let logger = Logger(
        subsystem: "com.chengxin.drivebatteryhealthviewer.chargelimitagent",
        category: "status-item"
    )
    var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var transitionTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var visibilityObservation: NSKeyValueObservation?
    private enum VisibilityTransition: Equatable {
        case appearing
        case disappearing
    }
    private var visibilityTransition: VisibilityTransition?
    private var isFading = false
    private var presentationAttempts = 0
    private var didCheckSafeAreaPlacement = false

    init(model: ChargeLimitAgentModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 330, height: 190)
        let popoverController = NSViewController()
        popoverController.view = FirstMouseHostingView(
            rootView: ChargeLimitAgentPopoverView(model: model)
        )
        popover.contentViewController = popoverController

        model.$status.combineLatest(model.$configuration)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reconcile() }
            .store(in: &cancellables)
        model.$language.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshContent() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.recoverPresentationIfNeeded() }
        .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.sessionDidBecomeActiveNotification
            ))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recoverPresentationIfNeeded() }
            .store(in: &cancellables)

        startRecoveryMonitoring()
        reconcile()
    }

    func invalidate() {
        transitionTask?.cancel()
        visibilityTransition = nil
        recoveryTask?.cancel()
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        cancellables.removeAll()
        popover.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func reconcile() {
        refreshContent()
        if model.shouldShowStatusItem {
            scheduleRevealAfterDelayIfNeeded()
        } else if !popover.isShown {
            beginFadeOut()
        }
    }

    /// Debounces the appearance without reserving an empty menu-bar slot.
    /// Once the condition has remained valid for the full delay, creation and
    /// the fade-in begin together so nearby status items never move early.
    private func scheduleRevealAfterDelayIfNeeded() {
        if let item = statusItem, item.statusBar != nil, item.isVisible {
            revealImmediately()
            return
        }
        guard visibilityTransition != .appearing else { return }

        transitionTask?.cancel()
        transitionTask = nil
        visibilityTransition = .appearing
        isFading = false
        transitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(Self.visibilityTransitionDelay * 1_000_000_000)
                )
            } catch { return }
            guard !Task.isCancelled,
                  self.visibilityTransition == .appearing,
                  self.statusItem == nil,
                  self.model.shouldShowStatusItem else {
                if self.visibilityTransition == .appearing, self.statusItem == nil {
                    self.transitionTask = nil
                    self.visibilityTransition = nil
                }
                return
            }
            self.transitionTask = nil
            self.visibilityTransition = nil
            self.revealImmediately()
        }
    }

    private func refreshContent() {
        let label = model.statusItemLabel
        statusItem?.button?.toolTip = label
        statusItem?.button?.setAccessibilityLabel(label)
        configureButtonIfAvailable()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            transitionTask?.cancel()
            transitionTask = nil
            visibilityTransition = nil
            isFading = false
            sender.alphaValue = 1
            // A menu-bar-only LSUIElement is not necessarily active when its
            // status item is clicked. Make the popover key immediately so the
            // next click reaches its control instead of merely activating it.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            DispatchQueue.main.async { [weak self] in
                self?.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard !model.shouldShowStatusItem else { return }
        beginFadeOut()
    }

    private func revealImmediately() {
        if visibilityTransition == .disappearing {
            let needsFadeIn = (statusItem?.button?.alphaValue ?? 1) < 0.999
            transitionTask?.cancel()
            transitionTask = nil
            visibilityTransition = nil
            isFading = false
            if let item = statusItem, needsFadeIn {
                beginFadeIn(of: item)
                return
            }
            statusItem?.button?.alphaValue = 1
        }

        let item: NSStatusItem
        let shouldAnimateAppearance: Bool
        if let current = statusItem, current.statusBar != nil {
            item = current
            shouldAnimateAppearance = !current.isVisible
        } else {
            discardBrokenStatusItem()
            seedSafePreferredPositionIfNeeded()
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            created.autosaveName = Self.statusItemAutosaveName
            created.behavior = []
            statusItem = created
            observeVisibility(of: created)
            item = created
            shouldAnimateAppearance = true
            logger.info("Created persistent charge-protection status item.")
        }

        item.length = NSStatusItem.squareLength
        item.isVisible = true
        presentationAttempts = 0
        finishPresentation(of: item, animatingAppearance: shouldAnimateAppearance)
    }

    private func finishPresentation(of item: NSStatusItem, animatingAppearance: Bool) {
        guard item === statusItem, item.statusBar != nil, item.isVisible else { return }
        if item.button != nil {
            configureButtonIfAvailable()
            if animatingAppearance {
                if visibilityTransition != .appearing {
                    item.button?.alphaValue = 0
                }
                beginFadeIn(of: item)
            } else if visibilityTransition == nil {
                item.button?.alphaValue = 1
            }
            presentationAttempts = 0
            scheduleSafeAreaPlacementCheck(for: item)
            return
        }

        guard presentationAttempts < Self.buttonAvailabilityRetryLimit else {
            logger.error("The status item did not obtain an NSStatusBarButton; scheduling recovery.")
            discardBrokenStatusItem()
            return
        }
        presentationAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak item] in
            guard let item else { return }
            self?.finishPresentation(of: item, animatingAppearance: animatingAppearance)
        }
    }

    private func beginFadeIn(of item: NSStatusItem) {
        transitionTask?.cancel()
        guard let button = item.button else { return }
        visibilityTransition = .appearing
        isFading = false
        let startingAlpha = button.alphaValue
        transitionTask = Task { [weak self, weak item] in
            guard let self, let item else { return }
            guard !Task.isCancelled,
                  self.visibilityTransition == .appearing,
                  self.statusItem === item,
                  self.model.shouldShowStatusItem else { return }
            let frameCount = Self.fadeFrameCount
            let frameDuration = Self.fadeDuration / Double(frameCount)
            for frame in 1...frameCount {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(frameDuration * 1_000_000_000)
                    )
                } catch { return }
                guard !Task.isCancelled,
                      self.statusItem === item,
                      self.visibilityTransition == .appearing,
                      self.model.shouldShowStatusItem else { return }
                let progress = Double(frame) / Double(frameCount)
                let eased = progress * progress * (3 - (2 * progress))
                button.alphaValue = startingAlpha + ((1 - startingAlpha) * eased)
            }
            button.alphaValue = 1
            self.transitionTask = nil
            self.visibilityTransition = nil
        }
    }

    private func beginFadeOut() {
        if visibilityTransition == .appearing, statusItem == nil {
            transitionTask?.cancel()
            transitionTask = nil
            visibilityTransition = nil
            isFading = false
            return
        }
        guard visibilityTransition != .disappearing,
              let item = statusItem,
              item.isVisible,
              let button = item.button else { return }
        transitionTask?.cancel()
        transitionTask = nil
        visibilityTransition = .disappearing
        isFading = true
        let startingAlpha = button.alphaValue
        transitionTask = Task { [weak self, weak item] in
            guard let self, let item else { return }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(Self.visibilityTransitionDelay * 1_000_000_000)
                )
            } catch { return }
            guard !Task.isCancelled,
                  self.visibilityTransition == .disappearing,
                  self.statusItem === item,
                  !self.popover.isShown,
                  !self.model.shouldShowStatusItem else { return }
            let frameCount = Self.fadeFrameCount
            let frameDuration = Self.fadeDuration / Double(frameCount)
            for frame in 1...frameCount {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(frameDuration * 1_000_000_000)
                    )
                } catch { return }
                guard !Task.isCancelled,
                      self.isFading,
                      self.visibilityTransition == .disappearing,
                      self.statusItem === item,
                      !self.popover.isShown,
                      !self.model.shouldShowStatusItem else { return }
                let progress = Double(frame) / Double(frameCount)
                let eased = progress * progress * (3 - (2 * progress))
                button.alphaValue = startingAlpha * (1 - eased)
            }

            guard self.isFading, self.statusItem === item else { return }
            button.alphaValue = 1
            self.isFading = false
            self.transitionTask = nil
            self.visibilityTransition = nil
            self.removeStatusItemForDisabledProtection()
        }
    }

    private func configureButtonIfAvailable() {
        guard let button = statusItem?.button else { return }
        button.image = Self.statusItemImage(for: model.presentationState)
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        let label = model.statusItemLabel
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func observeVisibility(of item: NSStatusItem) {
        visibilityObservation?.invalidate()
        visibilityObservation = item.observe(\.isVisible, options: [.new]) {
            [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor [weak self] in
                guard let self, self.model.shouldShowStatusItem else { return }
                self.logger.warning("AppKit hid the enabled protection status item; restoring it.")
                self.revealImmediately()
            }
        }
    }

    private func startRecoveryMonitoring() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(Self.recoveryInterval * 1_000_000_000)
                    )
                } catch { return }
                guard let self else { return }
                self.recoverPresentationIfNeeded()
            }
        }
    }

    private func recoverPresentationIfNeeded() {
        guard model.shouldShowStatusItem else {
            if !popover.isShown { beginFadeOut() }
            return
        }
        if visibilityTransition == .appearing, statusItem == nil { return }
        guard let item = statusItem,
              item.statusBar != nil,
              item.button != nil,
              item.isVisible else {
            logger.warning("Recovering a missing or incomplete protection status item.")
            revealImmediately()
            return
        }
        item.length = NSStatusItem.squareLength
        configureButtonIfAvailable()
        rememberCurrentPreferredPosition()
    }

    private func discardBrokenStatusItem() {
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        presentationAttempts = 0
    }

    private func seedSafePreferredPositionIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.preferredPositionDefaultsKey) == nil else { return }
        let remembered = (defaults.object(
            forKey: Self.rememberedPreferredPositionDefaultsKey
        ) as? NSNumber)?.doubleValue
        let position = remembered ?? Self.safePreferredPosition(for: NSScreen.main)
        defaults.set(position, forKey: Self.preferredPositionDefaultsKey)
        defaults.set(position, forKey: Self.rememberedPreferredPositionDefaultsKey)
    }

    private func scheduleSafeAreaPlacementCheck(for item: NSStatusItem) {
        guard !didCheckSafeAreaPlacement else { return }
        didCheckSafeAreaPlacement = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak item] in
            guard let self, let item, self.statusItem === item else { return }
            self.recoverFromObscuredSafeAreaIfNeeded(item)
        }
    }

    private func recoverFromObscuredSafeAreaIfNeeded(_ item: NSStatusItem) {
        guard let window = item.button?.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let safeRegions = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !safeRegions.isEmpty else { return }
        let frame = window.frame
        let isInVisibleTopArea = safeRegions.contains { region in
            region.minX <= frame.midX && frame.midX <= region.maxX
        }
        guard !isInVisibleTopArea else { return }

        logger.warning("The status item was placed in an obscured display area; moving it to the visible right-side menu area.")
        let safePosition = Self.safePreferredPosition(for: screen)
        UserDefaults.standard.set(safePosition, forKey: Self.preferredPositionDefaultsKey)
        UserDefaults.standard.set(
            safePosition,
            forKey: Self.rememberedPreferredPositionDefaultsKey
        )
        discardBrokenStatusItem()
        revealImmediately()
    }

    private func rememberCurrentPreferredPosition() {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(
            forKey: Self.preferredPositionDefaultsKey
        ) as? NSNumber else { return }
        defaults.set(
            value.doubleValue,
            forKey: Self.rememberedPreferredPositionDefaultsKey
        )
    }

    private func removeStatusItemForDisabledProtection() {
        rememberCurrentPreferredPosition()
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        presentationAttempts = 0
        didCheckSafeAreaPlacement = false
    }

    static func safePreferredPosition(for screen: NSScreen?) -> Double {
        guard let screen,
              let rightArea = screen.auxiliaryTopRightArea,
              !rightArea.isEmpty else { return fallbackPreferredPosition }
        let itemWidth = NSStatusItem.squareLength
        let maximumInsideRightArea = max(80, rightArea.width - itemWidth - 16)
        return Double(min(CGFloat(fallbackPreferredPosition), maximumInsideRightArea))
    }

    static func statusItemImage(for state: ChargeLimitAgentPresentationState) -> NSImage? {
        // Keep the same status item and saved position; only swap its glyph.
        switch state {
        case .systemCalibration, .systemCalibrationAwaitingConfirmation:
            return calibratingImage()
        case .protectionUnconfirmed:
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        default: return reachedLimitImage()
        }
    }

    /// The existing battery silhouette with two circular arrows cut out.
    /// Static template art stays legible and respects reduced motion.
    static func calibratingImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2.2, y: 2.65, width: 17.8, height: 10.7),
                         xRadius: 2.45, yRadius: 2.45).fill()
            NSBezierPath(roundedRect: NSRect(x: 20.4, y: 5.85, width: 1.85, height: 4.3),
                         xRadius: 0.8, yRadius: 0.8).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let center = NSPoint(x: 11.1, y: 8)
            for angles in [(CGFloat(150), CGFloat(20)), (CGFloat(330), CGFloat(200))] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 3.1, startAngle: angles.0,
                              endAngle: angles.1, clockwise: true)
                arc.lineWidth = 1.2
                arc.lineCapStyle = .round
                arc.stroke()
            }
            let upperHead = NSBezierPath()
            upperHead.move(to: NSPoint(x: 14.5, y: 7.9))
            upperHead.line(to: NSPoint(x: 12.9, y: 9.3))
            upperHead.line(to: NSPoint(x: 15.0, y: 9.5))
            upperHead.close(); upperHead.fill()
            let lowerHead = NSBezierPath()
            lowerHead.move(to: NSPoint(x: 7.7, y: 8.1))
            lowerHead.line(to: NSPoint(x: 7.2, y: 6.5))
            lowerHead.line(to: NSPoint(x: 9.3, y: 6.7))
            lowerHead.close(); lowerHead.fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// One solid, fully charged battery silhouette with a centered checkmark
    /// cut out of it. As a template image AppKit supplies the native menu-bar
    /// colour and automatically adapts to light and dark menu bars.
    static func reachedLimitImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            NSColor.black.setFill()
            let body = NSBezierPath(
                roundedRect: NSRect(x: 2.2, y: 2.65, width: 17.8, height: 10.7),
                xRadius: 2.45,
                yRadius: 2.45
            )
            body.fill()
            NSBezierPath(
                roundedRect: NSRect(x: 20.4, y: 5.85, width: 1.85, height: 4.3),
                xRadius: 0.8,
                yRadius: 0.8
            ).fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 6.9, y: 8.15))
            check.line(to: NSPoint(x: 9.75, y: 5.7))
            check.line(to: NSPoint(x: 15.4, y: 10.55))
            check.lineWidth = 1.75
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
