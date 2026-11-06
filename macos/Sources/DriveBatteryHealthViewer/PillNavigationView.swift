import AppKit
import QuartzCore

/// Four persistent destinations. Native radio buttons retain normal tracking,
/// keyboard focus and VoiceOver selection; only their drawing is customized.
@MainActor
final class PillNavigationView: NSStackView {
    private(set) var destinationButtons: [PillNavigationButton] = []
    var onSelect: ((SidebarDestination, Bool) -> Void)?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private let selectionView = NavigationSelectionView()
    private var selectedIndex: Int?
    private var keyboardActivation = false
    private let destinations = SidebarDestination.mainCases
    private var widthConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 0
        alignment = .centerY
        edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.radioGroup)
        identifier = NSUserInterfaceItemIdentifier("DBHV.Navigation")
        for (index, destination) in destinations.enumerated() {
            let button = PillNavigationButton(title: "", target: self, action: #selector(selectDestination(_:)))
            button.tag = index
            button.identifier = NSUserInterfaceItemIdentifier("DBHV.Navigation.\(destination.rawValue)")
            button.onMove = { [weak self] direction in self?.move(from: index, by: direction) }
            destinationButtons.append(button)
            addArrangedSubview(button)
        }
        selectionView.identifier = NSUserInterfaceItemIdentifier("DBHV.Navigation.Selection")
        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 14
        selectionView.setAccessibilityElement(false)
        addSubview(selectionView, positioned: .below, relativeTo: destinationButtons.first)
        widthConstraint = widthAnchor.constraint(equalToConstant: 260)
        NSLayoutConstraint.activate([widthConstraint, heightAnchor.constraint(equalToConstant: 34)])
    }

    required init?(coder: NSCoder) { nil }

    func update(model: AppModel) {
        var width: CGFloat = 6
        for (index, destination) in destinations.enumerated() {
            let button = destinationButtons[index]
            let title = model.t(destination == .history ? "historyNavigation" : destination.rawValue)
            if button.title != title { button.updateTitle(title) }
            button.state = (model.destination ?? .overview) == destination ? .on : .off
            button.toolTip = "\(title) (⌘\(index + 1))"
            width += button.intrinsicContentSize.width
        }
        if widthConstraint.constant != width { widthConstraint.constant = width; needsLayout = true }
        let index = destinations.firstIndex(of: model.destination ?? .overview) ?? 0
        if selectedIndex != index { selectedIndex = index; needsLayout = true }
        setAccessibilityLabel(model.t("appName"))
    }

    @objc private func selectDestination(_ sender: NSButton) {
        guard destinations.indices.contains(sender.tag) else { return }
        // Radio buttons can be activated by mouse, Space, or accessibility.
        let animate = !keyboardActivation && NSApp.currentEvent?.type != .keyDown && !reduceMotion()
        let changed = selectedIndex != sender.tag
        selectedIndex = sender.tag
        for button in destinationButtons { button.state = button === sender ? .on : .off }
        if changed { positionSelection(animated: animate) }
        onSelect?(destinations[sender.tag], animate)
    }

    private func move(from index: Int, by direction: Int) {
        let next = (index + direction + destinations.count) % destinations.count
        let button = destinationButtons[next]
        window?.makeFirstResponder(button)
        activate(index: next, animated: false)
    }

    func activate(index: Int, animated: Bool) {
        guard destinationButtons.indices.contains(index) else { return }
        keyboardActivation = !animated
        defer { keyboardActivation = false }
        selectDestination(destinationButtons[index])
    }

    override func layout() {
        super.layout()
        positionSelection(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSelectionColor()
    }

    private func updateSelectionColor() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectionView.layer?.backgroundColor = (dark ? NSColor.labelColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor).cgColor
        }
    }

    private func positionSelection(animated: Bool) {
        guard let selectedIndex, destinationButtons.indices.contains(selectedIndex), let layer = selectionView.layer else { return }
        let button = destinationButtons[selectedIndex]
        let target = button.convert(button.bounds, to: self)
        guard target.width > 0 && target.height > 0 else { return }
        updateSelectionColor()
        // Frequent polling/layout does not restart an in-flight transition.
        guard selectionView.frame != target else { return }
        let previous = layer.presentation() ?? layer
        let position = previous.position, bounds = previous.bounds
        let hadFrame = selectionView.frame.width > 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        selectionView.frame = target
        CATransaction.commit()
        layer.removeAnimation(forKey: "selection")
        if animated && hadFrame {
            let slide = CABasicAnimation(keyPath: "position")
            slide.fromValue = NSValue(point: position); slide.toValue = NSValue(point: layer.position)
            let resize = CABasicAnimation(keyPath: "bounds")
            resize.fromValue = NSValue(rect: bounds); resize.toValue = NSValue(rect: layer.bounds)
            let group = CAAnimationGroup()
            group.animations = [slide, resize]; group.duration = 0.20
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
            layer.add(group, forKey: "selection")
        }
    }

    var presentedSelectionFrame: NSRect {
        guard let layer = selectionView.layer?.presentation() ?? selectionView.layer else { return .zero }
        return NSRect(x: layer.position.x - layer.bounds.width * layer.anchorPoint.x,
                      y: layer.position.y - layer.bounds.height * layer.anchorPoint.y,
                      width: layer.bounds.width, height: layer.bounds.height)
    }

    var hasSelectionAnimation: Bool { selectionView.layer?.animation(forKey: "selection") != nil }

    override func draw(_ dirtyRect: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.labelColor.withAlphaComponent(contrast ? 0.15 : 0.075).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}

@MainActor
final class PillNavigationButton: NSButton {
    var onMove: ((Int) -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var itemWidth: CGFloat = 60
    // Native NSButton alignment insets vary with symbol metrics. This custom
    // bezel owns its complete bounds, so layout and painted bounds must agree.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: itemWidth, height: 28) }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); configure() }
    required init?(coder: NSCoder) { nil }

    private func configure() {
        wantsLayer = true
        setButtonType(.radio)
        isBordered = false
        focusRingType = .exterior
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setAccessibilityRole(.radioButton)
    }

    func updateTitle(_ text: String) {
        title = text
        setAccessibilityLabel(text)
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        itemWidth = max(56, ceil((text as NSString).size(withAttributes: [.font: font]).width) + 24)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        if (!selected && hovered) || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.10 : 0.04).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        }
        let font = NSFont.systemFont(ofSize: 14, weight: selected ? .semibold : .regular)
        let color = selected ? NSColor.systemBlue : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onMove?(-1)
        case 124: onMove?(1)
        default: super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
}

@MainActor
final class NavigationWindow: NSWindow {
    var selectDestination: ((Int) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let number = Int(event.charactersIgnoringModifiers ?? ""), (1...SidebarDestination.mainCases.count).contains(number),
           let selectDestination {
            selectDestination(number - 1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class NavigationSelectionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
