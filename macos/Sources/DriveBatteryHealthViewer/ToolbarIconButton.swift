import AppKit

enum ToolbarMetrics {
    static let buttonSide: CGFloat = 32
    static let symbolSide: CGFloat = 20
    static let symbolPointSize: CGFloat = 17
    static let cornerRadius: CGFloat = 6
    static let spacing: CGFloat = 8
}

/// One geometry/drawing path for every toolbar icon, including sidebar and
/// privacy. NSButton retains action, tracking, keyboard and accessibility roles.
@MainActor
final class ToolbarIconButton: NSButton {
    private struct Artwork {
        let image: NSImage
        let ink: NSRect
    }
    private static var artworkCache: [String: Artwork] = [:]
    private var artwork: Artwork?
    private var symbolName = ""
    private var pointerInside = false
    private var hoverTrackingArea: NSTrackingArea?

    init(symbol: String, target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: ToolbarMetrics.buttonSide, height: ToolbarMetrics.buttonSide))
        self.target = target
        self.action = action
        imagePosition = .imageOnly
        isBordered = false
        focusRingType = .exterior
        wantsLayer = true
        setSymbol(symbol)
    }

    required init?(coder: NSCoder) { nil }
    // Native NSButton alignment insets vary with symbol metrics. This custom
    // bezel owns its complete bounds, so layout and painted bounds must agree.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: ToolbarMetrics.buttonSide, height: ToolbarMetrics.buttonSide)
    }

    func setSymbol(_ name: String) {
        guard symbolName != name else { return }
        symbolName = name
        if let cached = Self.artworkCache[name] { artwork = cached }
        else if let prepared = Self.prepare(name) {
            Self.artworkCache[name] = prepared
            artwork = prepared
        }
        image = artwork?.image
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTrackingArea = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        if isEnabled && (pointerInside || selected || isHighlighted) {
            let opacity: CGFloat = isHighlighted ? 0.16 : selected ? 0.10 : 0.07
            NSColor.labelColor.withAlphaComponent(opacity).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: ToolbarMetrics.cornerRadius,
                         yRadius: ToolbarMetrics.cornerRadius).fill()
        }
        guard let artwork else { return }
        let tint = isEnabled ? NSColor.labelColor.withAlphaComponent(selected ? 0.82 : 0.66) : .disabledControlTextColor
        guard let symbol = artwork.image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint])) else { return }
        symbol.isTemplate = false
        let ink = artwork.ink
        let scale = min(1, ToolbarMetrics.symbolSide / ink.width, ToolbarMetrics.symbolSide / ink.height)
        // Bitmap ink bounds are converted to image coordinates in prepare().
        // This view is flipped, so its image center is measured from the top.
        let destination = NSRect(
            x: bounds.midX - ink.midX * scale,
            y: bounds.midY - (artwork.image.size.height - ink.midY) * scale,
            width: artwork.image.size.width * scale, height: artwork.image.size.height * scale)
        symbol.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: ToolbarMetrics.cornerRadius,
                     yRadius: ToolbarMetrics.cornerRadius).fill()
    }

    private static func prepare(_ name: String) -> Artwork? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: ToolbarMetrics.symbolPointSize, weight: .regular)) else { return nil }
        let scale: CGFloat = 4
        let width = Int(ceil(image.size.width * scale)), height = Int(ceil(image.size.height * scale))
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap),
              let data = bitmap.bitmapData,
              let mask = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black])) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        mask.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: false, hints: nil)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        var minX = width, minY = height, maxX = -1, maxY = -1
        let stride = bitmap.bytesPerRow
        for y in 0..<height {
            for x in 0..<width where data[y * stride + x * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // NSBitmapImageRep rows start at the top; NSImage coordinates do not.
        let ink = NSRect(x: CGFloat(minX) / scale, y: image.size.height - CGFloat(maxY + 1) / scale,
                         width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        return Artwork(image: image, ink: ink)
    }
}
