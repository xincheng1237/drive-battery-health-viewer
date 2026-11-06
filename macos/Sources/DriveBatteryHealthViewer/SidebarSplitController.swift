import AppKit
import QuartzCore

/// Keep hosting controllers mounted and animate their frames through AppKit,
/// without an animated constraint solver or per-frame application layout loop.
/// Repeated inputs retarget the compositor; only the newest completion may hide
/// the sidebar. Window geometry remains owned by the native split view.
@MainActor
final class SidebarSplitController: NSViewController, NSSplitViewDelegate {
    let splitView = SidebarSplitView()
    private let sidebar: NSViewController
    private let detail: NSViewController
    private let sidebarClip = NSVisualEffectView()
    private let dividerView = NSBox()
    private var animationGeneration: UInt = 0
    private var isAnimating = false
    private var expandedWidth: CGFloat = 220
    private var layingOut = false
    private(set) var isSidebarCollapsed = false

    init(sidebar: NSViewController, detail: NSViewController) {
        self.sidebar = sidebar
        self.detail = detail
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        view = splitView
        addChild(sidebar)
        addChild(detail)
        sidebarClip.material = .sidebar
        sidebarClip.blendingMode = .behindWindow
        sidebarClip.state = .followsWindowActiveState
        sidebarClip.wantsLayer = true
        sidebarClip.layer?.masksToBounds = true
        sidebarClip.addSubview(sidebar.view)
        dividerView.boxType = .separator
        dividerView.identifier = NSUserInterfaceItemIdentifier("DBHV.SidebarDivider")
        dividerView.setAccessibilityElement(false)
        sidebarClip.addSubview(dividerView)
        splitView.addSubview(sidebarClip)
        splitView.addSubview(detail.view)
        layoutPanes()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        isSidebarCollapsed.toggle()
        animationGeneration &+= 1
        let generation = animationGeneration
        sidebarClip.isHidden = false
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            layoutPanes(animated: true)
        } completionHandler: { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.isAnimating = false
            if self.isSidebarCollapsed { self.sidebarClip.isHidden = true }
        }
    }

    private func layoutPanes(animated: Bool = false) {
        guard !layingOut, isViewLoaded else { return }
        layingOut = true
        defer { layingOut = false }
        let bounds = splitView.bounds
        let width = isSidebarCollapsed ? 0 : min(expandedWidth, max(0, bounds.width - 400))
        let divider: CGFloat = width > 0 ? splitView.dividerThickness : 0
        if !animated { sidebarClip.isHidden = width == 0 && isSidebarCollapsed }
        let clip = animated ? sidebarClip.animator() : sidebarClip
        let content = animated ? detail.view.animator() : detail.view
        let separator = animated ? dividerView.animator() : dividerView
        clip.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        separator.frame = NSRect(x: width - 1, y: 0, width: 1, height: bounds.height)
        splitView.needsDisplay = true
        // Clip a stable-width sidebar; its text and selection never compress.
        sidebar.view.frame = NSRect(x: 0, y: 0, width: expandedWidth, height: bounds.height)
        content.frame = NSRect(x: width + divider, y: 0,
                                  width: max(0, bounds.width - width - divider), height: bounds.height)
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        // A window resize supersedes any old animation's endpoint geometry.
        animationGeneration &+= 1
        isAnimating = false
        sidebarClip.layer?.removeAllAnimations()
        detail.view.layer?.removeAllAnimations()
        layoutPanes()
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        isSidebarCollapsed && !isAnimating
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat { 190 }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat { min(270, splitView.bounds.width - 400) }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !layingOut, !isAnimating, !isSidebarCollapsed,
              let event = NSApp.currentEvent, event.type == .leftMouseDragged else { return }
        expandedWidth = min(270, max(190, sidebarClip.frame.width))
        layoutPanes()
    }
}

/// Divider geometry is composited inside the clipped sidebar. The standard
/// divider painter otherwise retains its previous pane position while frames
/// animate independently, leaving a vertical line after a completed collapse.
@MainActor
final class SidebarSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {}
}
