import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("Usage: RenderDMGBackground.swift <1x.png> <2x.png> <version>\n".utf8))
    exit(2)
}

let output1x = URL(fileURLWithPath: CommandLine.arguments[1])
let output2x = URL(fileURLWithPath: CommandLine.arguments[2])
let version = CommandLine.arguments[3]
let logicalSize = NSSize(width: 720, height: 450)

func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

func centeredText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func render(scale: Int, to destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(logicalSize.width) * scale,
        pixelsHigh: Int(logicalSize.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "DMGBackground", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.imageInterpolation = .high

    let canvas = NSRect(origin: .zero, size: logicalSize)
    NSGradient(
        starting: color(248, 251, 255),
        ending: color(231, 241, 255)
    )?.draw(in: canvas, angle: 90)

    color(47, 143, 247, alpha: 0.08).setFill()
    NSBezierPath(ovalIn: NSRect(x: -90, y: 270, width: 330, height: 260)).fill()
    color(77, 189, 255, alpha: 0.07).setFill()
    NSBezierPath(ovalIn: NSRect(x: 520, y: -70, width: 280, height: 250)).fill()

    centeredText(
        "安装硬盘与电池健康查看器",
        rect: NSRect(x: 60, y: 374, width: 600, height: 38),
        font: .systemFont(ofSize: 27, weight: .semibold),
        color: color(30, 38, 50)
    )
    centeredText(
        "将应用拖到“应用程序”文件夹  ·  Drag the app to Applications",
        rect: NSRect(x: 70, y: 341, width: 580, height: 24),
        font: .systemFont(ofSize: 13.5, weight: .medium),
        color: color(91, 103, 121)
    )

    let tileFill = color(255, 255, 255, alpha: 0.72)
    let tileStroke = color(47, 143, 247, alpha: 0.12)
    drawRoundedRect(NSRect(x: 102, y: 128, width: 176, height: 182), radius: 30, fill: tileFill, stroke: tileStroke)
    drawRoundedRect(NSRect(x: 442, y: 128, width: 176, height: 182), radius: 30, fill: tileFill, stroke: tileStroke)

    drawRoundedRect(
        NSRect(x: 305, y: 199, width: 110, height: 48),
        radius: 24,
        fill: color(47, 143, 247, alpha: 0.12)
    )
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 326, y: 223))
    arrow.line(to: NSPoint(x: 391, y: 223))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(27, 132, 255).setStroke()
    arrow.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: NSPoint(x: 381, y: 236))
    arrowHead.line(to: NSPoint(x: 396, y: 223))
    arrowHead.line(to: NSPoint(x: 381, y: 210))
    arrowHead.lineCapStyle = .round
    arrowHead.lineJoinStyle = .round
    arrowHead.lineWidth = 5
    color(27, 132, 255).setStroke()
    arrowHead.stroke()

    centeredText(
        "Drive & Battery Health Viewer  ·  v\(version)",
        rect: NSRect(x: 80, y: 35, width: 560, height: 22),
        font: .systemFont(ofSize: 11.5, weight: .medium),
        color: color(111, 124, 143)
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        throw NSError(domain: "DMGBackground", code: 2)
    }
    try data.write(to: destination, options: .atomic)
}

try render(scale: 1, to: output1x)
try render(scale: 2, to: output2x)
