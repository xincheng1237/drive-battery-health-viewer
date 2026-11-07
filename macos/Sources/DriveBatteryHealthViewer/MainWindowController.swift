import AppKit
import Combine
import QuartzCore
import SwiftUI

/// AppKit owns stable navigation and toolbar placement.
/// SwiftUI pages cannot install a second toolbar or move content into chrome.
@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    static let minimumContentWidth: CGFloat = 600
    private let model: AppModel
    private let containerController = NSViewController()
    private let contentSurface = ContentEdgeView()
    let detailController: NSViewController
    let navigationHeader = PillNavigationView()
    private let actionsView = NSStackView()
    private let refreshSlot = NSView()
    private let progress = NSProgressIndicator()
    private var buttons: [String: ToolbarIconButton] = [:]
    private var observation: AnyCancellable?
    private var resizeObservation: AnyCancellable?
    private var updateScheduled = false
    private var lastPrivacyState: Bool?
    private let toolbarID = NSToolbar.Identifier("DBHV.NativeMainToolbar.v1")
    private let navigationID = NSToolbarItem.Identifier("DBHV.NavigationHeader")
    private let actionsID = NSToolbarItem.Identifier("DBHV.OverviewActions")

    init(model: AppModel, persistsFrame: Bool = true) {
        self.model = model
        let detail = NSHostingController(rootView: RootView().environmentObject(model))
        detail.sizingOptions = []
        if #available(macOS 13.3, *) { detail.safeAreaRegions = [] }
        detail.view.wantsLayer = true
        detail.view.layer?.masksToBounds = true
        detailController = detail

        let window = NavigationWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 780),
                              styleMask: MainWindowLayout.styleMask, backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Self.minimumContentWidth, height: 520)
        MainWindowLayout.configure(window)

        let container = NSView()
        container.wantsLayer = true
        let background = WindowCanvasView()
        background.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        containerController.view = container
        containerController.addChild(detailController)
        window.contentViewController = containerController
        let content = detailController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        contentSurface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentSurface)
        contentSurface.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor)
        ])
        guard let guide = window.contentLayoutGuide as? NSLayoutGuide else {
            preconditionFailure("A titled window must provide its content layout guide")
        }
        NSLayoutConstraint.activate([
            contentSurface.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: guide.topAnchor),
            contentSurface.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
        configureNavigationHeader()
        configureActions()
        let toolbar = NSToolbar(identifier: toolbarID)
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [navigationID]
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        window.toolbar = toolbar
        container.layoutSubtreeIfNeeded()
        if persistsFrame {
            let name = "DriveBatteryHealthViewer.MainWindow"
            if !window.setFrameUsingName(name) { window.center() }
            window.setFrameAutosaveName(name)
        }
        resizeObservation = NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
            .sink { [weak self] _ in self?.updateToolbarAlignment() }
        updateToolbarAlignment()
        refreshToolbarState()
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self, !self.updateScheduled else { return }
            self.updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.updateScheduled = false
                self?.refreshToolbarState()
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    private func updateToolbarAlignment() {
        guard let window, let toolbar = window.toolbar else { return }
        // Let the toolbar flow after the window controls when the centered
        // navigation and the five overview actions need the same space.
        let centered: Set<NSToolbarItem.Identifier> = window.frame.width >= 720 ? [navigationID] : []
        if toolbar.centeredItemIdentifiers != centered { toolbar.centeredItemIdentifiers = centered }
    }

    private func configureNavigationHeader() {
        navigationHeader.update(model: model)
        navigationHeader.onSelect = { [weak self] destination, animated in
            guard let self, self.model.destination != destination else { return }
            let animation: Animation? = animated ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.16) : nil
            var transaction = Transaction(animation: animation)
            transaction.disablesAnimations = !animated
            withTransaction(transaction) { self.model.destination = destination }
        }
        (window as? NavigationWindow)?.selectDestination = { [weak self] index in
            guard let self, SidebarDestination.mainCases.indices.contains(index) else { return }
            self.navigationHeader.activate(index: index, animated: false)
        }
    }

    private func configureActions() {
        actionsView.orientation = .horizontal
        actionsView.spacing = ToolbarMetrics.spacing
        actionsView.edgeInsets = NSEdgeInsets()
        actionsView.alignment = .centerY
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        actionsView.widthAnchor.constraint(equalToConstant: ToolbarMetrics.buttonSide * 5 + ToolbarMetrics.spacing * 4).isActive = true
        actionsView.heightAnchor.constraint(equalToConstant: ToolbarMetrics.buttonSide).isActive = true
        for (key, symbol, action) in [
            ("refresh", "arrow.clockwise", #selector(refresh)),
            ("exportReport", "square.and.arrow.down", #selector(exportReport)),
            ("copyReport", "doc.on.doc", #selector(copyReport)),
            ("report", "doc.text.magnifyingglass", #selector(showReport)),
            ("hideSerials", "eye.slash", #selector(togglePrivacy))
        ] {
            let button = makeButton(key: key, symbol: symbol, action: action)
            buttons[key] = button
            if key == "refresh" {
                refreshSlot.translatesAutoresizingMaskIntoConstraints = false
                refreshSlot.addSubview(button)
                button.centerXAnchor.constraint(equalTo: refreshSlot.centerXAnchor).isActive = true
                button.centerYAnchor.constraint(equalTo: refreshSlot.centerYAnchor).isActive = true
                progress.style = .spinning
                progress.controlSize = .small
                progress.isDisplayedWhenStopped = false
                progress.translatesAutoresizingMaskIntoConstraints = false
                refreshSlot.addSubview(progress)
                NSLayoutConstraint.activate([
                    refreshSlot.widthAnchor.constraint(equalToConstant: ToolbarMetrics.buttonSide),
                    refreshSlot.heightAnchor.constraint(equalToConstant: ToolbarMetrics.buttonSide),
                    progress.centerXAnchor.constraint(equalTo: refreshSlot.centerXAnchor),
                    progress.centerYAnchor.constraint(equalTo: refreshSlot.centerYAnchor),
                    progress.widthAnchor.constraint(equalToConstant: 16),
                    progress.heightAnchor.constraint(equalToConstant: 16)
                ])
                actionsView.addArrangedSubview(refreshSlot)
            } else {
                actionsView.addArrangedSubview(button)
            }
        }
        buttons["hideSerials"]?.setButtonType(.onOff)
    }

    private func makeButton(key: String, symbol: String, action: Selector) -> ToolbarIconButton {
        let button = ToolbarIconButton(symbol: symbol, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier("DBHV.Toolbar.\(key)")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: ToolbarMetrics.buttonSide).isActive = true
        button.heightAnchor.constraint(equalToConstant: ToolbarMetrics.buttonSide).isActive = true
        return button
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [navigationID, .flexibleSpace, actionsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier == navigationID {
            item.view = navigationHeader
            item.visibilityPriority = .high
        } else if identifier == actionsID {
            item.view = actionsView
            item.visibilityPriority = .high
        } else { return nil }
        return item
    }

    private func refreshToolbarState() {
        let destination = model.destination ?? .overview
        let title = model.t(destination.rawValue)
        navigationHeader.update(model: model)
        // These operations act on the current overview snapshot. Other pages
        // own their own actions; keep the slot so navigation never shifts.
        actionsView.isHidden = destination != .overview
        if window?.title != title { window?.title = title }
        for (key, button) in buttons {
            let text = model.t(key)
            button.toolTip = text
            button.setAccessibilityLabel(text)
        }
        let hasReport = model.currentSnapshot != nil
        buttons["refresh"]?.isEnabled = !model.isScanning
        for key in ["exportReport", "copyReport", "report"] { buttons[key]?.isEnabled = hasReport }
        buttons["refresh"]?.isHidden = model.isScanning
        if model.isScanning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        buttons["hideSerials"]?.state = model.hideSerials ? .on : .off
        let privacyImage = model.hideSerials ? "eye.slash" : "eye"
        if lastPrivacyState != model.hideSerials {
            lastPrivacyState = model.hideSerials
            buttons["hideSerials"]?.setSymbol(privacyImage)
        }
        // Keep toolbar identity/width unchanged across navigation and
        // page updates. Report operations remain available for the last scan.
    }

    @objc private func refresh() { model.refresh() }
    @objc private func exportReport() { model.presentExportCurrentReportPanel() }
    @objc private func copyReport() { model.copyCurrentReport() }
    @objc private func showReport() { model.showsTextReport = true }
    @objc private func togglePrivacy() { model.hideSerials.toggle() }

    /// Presentation geometry follows the actual composited layers instead of
    /// the host view's fixed backing width during a clipping animation.
    func presentedFrame(of view: NSView) -> NSRect? {
        var host: NSView? = view
        while let current = host {
            if let layer = current.layer?.presentation() {
                return layer.convert(view.convert(view.bounds, to: current), to: nil)
            }
            host = current.superview
        }
        return nil
    }

    func actionPresentationFrames() -> [String: NSRect] {
        Dictionary(uniqueKeysWithValues: ["refresh", "exportReport", "copyReport", "report", "hideSerials"].compactMap { key in
            guard let button = buttons[key], let frame = presentedFrame(of: button) else { return nil }
            return (key, frame)
        })
    }

    /// Geometry from the actual production controls, used by dynamic tests.
    func actionFramesInWindow() -> [String: NSRect] {
        Dictionary(uniqueKeysWithValues: ["refresh", "exportReport", "copyReport", "report", "hideSerials"].compactMap { key in
            guard let button = buttons[key] else { return nil }
            return (key, button.convert(button.bounds, to: nil))
        })
    }
}

/// The same semantic canvas fills content and transparent window chrome. No
/// separate toolbar material, border or scroll-dependent separator is drawn.
@MainActor
private final class WindowCanvasView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}

/// A small transparent scroll edge, rather than an opaque toolbar-width band.
/// The mask only affects the last 12pt at the content's top clipping boundary.
@MainActor
private final class ContentEdgeView: NSView {
    private let edgeMask = CAGradientLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        edgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.endPoint = CGPoint(x: 0.5, y: 1)
        edgeMask.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        layer?.mask = edgeMask
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        edgeMask.frame = bounds
        edgeMask.locations = [0, NSNumber(value: max(0, 1 - 12 / max(1, Double(bounds.height)))), 1]
        CATransaction.commit()
    }
}
