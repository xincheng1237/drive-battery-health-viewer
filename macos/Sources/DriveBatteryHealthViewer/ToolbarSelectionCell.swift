import AppKit

/// Keep AppKit's native rollover/selection bezel. Its generic on/off image
/// treatment washes out this template symbol in an inactive toolbar; draw the
/// selected symbol with the same adaptive foreground used by the old toggle.
@MainActor
final class ToolbarSelectionCell: NSButtonCell {
    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        guard state == .on,
              let symbol = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))),
              let colored = symbol.copy() as? NSImage else {
            super.drawImage(image, withFrame: frame, in: controlView)
            return
        }
        colored.isTemplate = false
        // `frame` is a cell content rect, not the symbol's aspect-ratio rect.
        // Draw at natural size; stretching it flattens eye.slash in a toolbar.
        let size = colored.size
        let destination = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                 width: size.width, height: size.height)
        colored.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 0.72,
                     respectFlipped: controlView.isFlipped, hints: nil)
    }
}
