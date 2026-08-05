import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: CreateICNS.swift <iconset> <output.icns>\n".utf8))
    exit(2)
}

let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let representations: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

var chunks = Data()
for (type, filename) in representations {
    let png = try Data(contentsOf: sourceDirectory.appendingPathComponent(filename))
    chunks.append(contentsOf: type.utf8)
    chunks.append(bigEndianBytes(UInt32(png.count + 8)))
    chunks.append(png)
}

var result = Data("icns".utf8)
result.append(bigEndianBytes(UInt32(chunks.count + 8)))
result.append(chunks)
try result.write(to: outputURL, options: .atomic)
