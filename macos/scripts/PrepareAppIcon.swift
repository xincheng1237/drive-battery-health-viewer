import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: PrepareAppIcon.swift <source.png> <output.png>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("Unable to load source icon.\n".utf8))
    exit(3)
}

let canvasSize = NSSize(width: 1024, height: 1024)
let artworkSize = NSSize(width: 880, height: 880)
let artworkRect = NSRect(
    x: (canvasSize.width - artworkSize.width) / 2,
    y: (canvasSize.height - artworkSize.height) / 2,
    width: artworkSize.width,
    height: artworkSize.height
)

let canvas = NSImage(size: canvasSize)
canvas.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill(using: .copy)
source.draw(
    in: artworkRect,
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1
)
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Unable to render padded icon.\n".utf8))
    exit(4)
}
try png.write(to: outputURL, options: .atomic)
