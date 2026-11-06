import AppKit
import Testing
@testable import DriveBatteryHealthViewer

@Suite("Unified toolbar geometry", .serialized)
struct ToolbarGeometryTests {
    private let symbols = ["sidebar.left", "arrow.clockwise", "square.and.arrow.down", "doc.on.doc", "doc.text.magnifyingglass", "eye.slash", "eye"]

    @MainActor private func enter(_ button: ToolbarIconButton) throws {
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        button.mouseEntered(with: event)
    }

    @Test @MainActor func squareHoverAndVisibleInkAreCenteredForEverySymbol() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            for name in symbols {
                let button = ToolbarIconButton(symbol: name, target: nil, action: nil)
                button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
                try enter(button)
                let pixels = 128
                let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32))
                let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState()
                let cg = context.cgContext
                cg.scaleBy(x: 4, y: 4); cg.translateBy(x: 0, y: 32); cg.scaleBy(x: 1, y: -1)
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                appearance.performAsCurrentDrawingAppearance { button.draw(button.bounds) }
                context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
                let data = try #require(bitmap.bitmapData)
                func box(alpha: UInt8) -> NSRect {
                    var x0 = pixels, y0 = pixels, x1 = -1, y1 = -1
                    for y in 0..<pixels { for x in 0..<pixels where data[y * bitmap.bytesPerRow + x * 4 + 3] > alpha {
                        x0 = min(x0,x); x1 = max(x1,x); y0 = min(y0,y); y1 = max(y1,y)
                    } }
                    return NSRect(x:x0,y:y0,width:max(0,x1-x0+1),height:max(0,y1-y0+1))
                }
                let background = box(alpha: 8), ink = box(alpha: 31)
                #expect(background.width == background.height, "Non-square hover for \(name)")
                #expect(ink.width > 0 && ink.height > 0)
                #expect(abs(ink.midX - background.midX) <= 1.5, "Unequal left/right inset for \(name): \(ink)")
                #expect(abs(ink.midY - background.midY) <= 1.5, "Unequal top/bottom inset for \(name): \(ink)")
                #expect(max(ink.width, ink.height) <= 82)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DBHV_TOOLBAR_GEOMETRY_PREVIEW"] != nil))
    @MainActor func renderEveryHoverAndSelection() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DBHV_TOOLBAR_GEOMETRY_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let canvas = ToolbarGeometryCanvas(frame:NSRect(x:0,y:0,width:580,height:280))
            let labels = ["侧栏", "刷新", "保存", "复制", "报告", "隐私"]
            for i in 0..<6 {
                let label = NSTextField(labelWithString: labels[i]); label.font = .systemFont(ofSize:12)
                label.frame = NSRect(x:82+i*76,y:15,width:68,height:20); label.alignment = .center;canvas.addSubview(label)
            }
            for row in 0..<3 {
                let label = NSTextField(labelWithString: ["正常", "悬停", "选中"][row]);label.font = .systemFont(ofSize:12)
                label.frame=NSRect(x:16,y:61+row*76,width:50,height:20);canvas.addSubview(label)
                for i in 0..<6 {
                    let button = ToolbarIconButton(symbol:symbols[i],target:nil,action:nil)
                    button.frame=NSRect(x:100+i*76,y:52+row*76,width:32,height:32)
                    if row==1 { try enter(button) }
                    if row==2 { button.state = .on }
                    canvas.addSubview(button)
                }
            }
            let window=NSWindow(contentRect:canvas.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            window.contentView=canvas;window.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
            let bitmap=try #require(canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds))
            window.effectiveAppearance.performAsCurrentDrawingAppearance { canvas.cacheDisplay(in:canvas.bounds,to:bitmap) }
            try #require(bitmap.representation(using:.png,properties:[:])).write(to:folder.appendingPathComponent("six-buttons-\(dark ? "dark":"light").png"))
            window.close()
        }
    }
}

@MainActor private final class ToolbarGeometryCanvas:NSView {
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}
