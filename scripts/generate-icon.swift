#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let fileManager = FileManager.default
private let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
private let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let resourcesDirectory = projectRoot.appendingPathComponent("Resources", isDirectory: true)
private let destination = resourcesDirectory.appendingPathComponent("AppIcon.icns")
private let temporaryRoot = fileManager.temporaryDirectory
    .appendingPathComponent("QuotaPet-icon-\(UUID().uuidString)", isDirectory: true)
private let iconset = temporaryRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
private let temporaryOutput = resourcesDirectory
    .appendingPathComponent(".AppIcon-\(UUID().uuidString).icns")

private struct ICNSChunk {
    let type: String
    let fileName: String
    let pixels: Int
}

// macOS 26 iconutil can reject a complete bitmap iconset while still being able
// to read ICNS files. This standard chunk map is used only if iconutil packing fails.
private let fallbackChunks: [ICNSChunk] = [
    .init(type: "icp4", fileName: "icon_16x16.png", pixels: 16),
    .init(type: "icp5", fileName: "icon_32x32.png", pixels: 32),
    .init(type: "icp6", fileName: "icon_32x32@2x.png", pixels: 64),
    .init(type: "ic07", fileName: "icon_128x128.png", pixels: 128),
    .init(type: "ic08", fileName: "icon_256x256.png", pixels: 256),
    .init(type: "ic09", fileName: "icon_512x512.png", pixels: 512),
    .init(type: "ic10", fileName: "icon_512x512@2x.png", pixels: 1024),
    .init(type: "ic11", fileName: "icon_16x16@2x.png", pixels: 32),
    .init(type: "ic12", fileName: "icon_32x32@2x.png", pixels: 64),
    .init(type: "ic13", fileName: "icon_128x128@2x.png", pixels: 256),
    .init(type: "ic14", fileName: "icon_256x256@2x.png", pixels: 512),
]

defer {
    try? fileManager.removeItem(at: temporaryRoot)
    try? fileManager.removeItem(at: temporaryOutput)
}

func drawIcon(pixels: Int, destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "QuotaPet.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    let scale = CGFloat(pixels) / 1024
    let context = graphics.cgContext
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    let background = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 224, yRadius: 224)
    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.31, alpha: 1),
    ])!
    backgroundGradient.draw(in: background, angle: -55)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    let dumpling = NSBezierPath(roundedRect: NSRect(x: 260, y: 242, width: 504, height: 500), xRadius: 246, yRadius: 246)
    NSColor(calibratedRed: 0.965, green: 0.95, blue: 0.89, alpha: 1).setFill()
    dumpling.fill()
    context.restoreGState()

    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(82)
    context.setStrokeColor(NSColor(calibratedRed: 0.23, green: 0.91, blue: 0.82, alpha: 1).cgColor)
    context.addArc(
        center: CGPoint(x: 512, y: 500),
        radius: 310,
        startAngle: -.pi * 0.18,
        endAngle: .pi * 1.48,
        clockwise: false
    )
    context.strokePath()

    context.setLineWidth(70)
    context.move(to: CGPoint(x: 760, y: 314))
    context.addCurve(
        to: CGPoint(x: 858, y: 242),
        control1: CGPoint(x: 800, y: 280),
        control2: CGPoint(x: 820, y: 234)
    )
    context.addCurve(
        to: CGPoint(x: 890, y: 324),
        control1: CGPoint(x: 900, y: 250),
        control2: CGPoint(x: 918, y: 286)
    )
    context.strokePath()
    context.restoreGState()

    let faceColor = NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.24, alpha: 1)
    faceColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: 408, y: 476, width: 54, height: 68)).fill()
    NSBezierPath(ovalIn: NSRect(x: 562, y: 476, width: 54, height: 68)).fill()

    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: 468, y: 430))
    smile.curve(to: NSPoint(x: 556, y: 430), controlPoint1: NSPoint(x: 488, y: 402), controlPoint2: NSPoint(x: 536, y: 402))
    smile.lineWidth = 24
    smile.lineCapStyle = .round
    faceColor.setStroke()
    smile.stroke()

    guard let image = bitmap.cgImage,
          let encoder = CGImageDestinationCreateWithURL(
              destination as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          )
    else {
        throw NSError(domain: "QuotaPet.Icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG encoder"])
    }
    CGImageDestinationAddImage(encoder, image, [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary)
    guard CGImageDestinationFinalize(encoder) else {
        throw NSError(domain: "QuotaPet.Icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PNG"])
    }
}

private func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

private func bigEndianUInt32(in data: Data, at offset: Int) throws -> UInt32 {
    guard offset >= 0, offset + 4 <= data.count else {
        throw NSError(domain: "QuotaPet.Icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Truncated ICNS integer"])
    }
    return data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

private func writeFallbackICNS(iconset: URL, output: URL) throws {
    var body = Data()
    for chunk in fallbackChunks {
        let typeData = Data(chunk.type.utf8)
        guard typeData.count == 4 else {
            throw NSError(domain: "QuotaPet.Icon", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid ICNS chunk type"])
        }
        let payload = try Data(contentsOf: iconset.appendingPathComponent(chunk.fileName))
        guard let image = NSBitmapImageRep(data: payload),
              image.pixelsWide == chunk.pixels,
              image.pixelsHigh == chunk.pixels
        else {
            throw NSError(domain: "QuotaPet.Icon", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unexpected PNG size for \(chunk.type)"])
        }
        guard payload.count <= Int(UInt32.max) - 8 else {
            throw NSError(domain: "QuotaPet.Icon", code: 7, userInfo: [NSLocalizedDescriptionKey: "ICNS chunk is too large"])
        }
        body.append(typeData)
        appendBigEndian(UInt32(payload.count + 8), to: &body)
        body.append(payload)
    }

    guard body.count <= Int(UInt32.max) - 8 else {
        throw NSError(domain: "QuotaPet.Icon", code: 8, userInfo: [NSLocalizedDescriptionKey: "ICNS file is too large"])
    }
    var container = Data("icns".utf8)
    appendBigEndian(UInt32(body.count + 8), to: &container)
    container.append(body)
    try validateFallbackICNS(container)
    try container.write(to: output, options: .atomic)
}

private func validateFallbackICNS(_ data: Data) throws {
    guard data.count >= 8,
          String(data: data.prefix(4), encoding: .ascii) == "icns",
          try bigEndianUInt32(in: data, at: 4) == UInt32(data.count)
    else {
        throw NSError(domain: "QuotaPet.Icon", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid ICNS container header"])
    }

    var offset = 8
    var actualTypes: [String] = []
    while offset < data.count {
        guard offset + 8 <= data.count,
              let type = String(data: data[offset..<(offset + 4)], encoding: .ascii)
        else {
            throw NSError(domain: "QuotaPet.Icon", code: 10, userInfo: [NSLocalizedDescriptionKey: "Truncated ICNS chunk header"])
        }
        let length = Int(try bigEndianUInt32(in: data, at: offset + 4))
        guard length >= 8, offset + length <= data.count else {
            throw NSError(domain: "QuotaPet.Icon", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid ICNS chunk length"])
        }
        actualTypes.append(type)
        offset += length
    }
    guard offset == data.count, actualTypes == fallbackChunks.map(\.type) else {
        throw NSError(domain: "QuotaPet.Icon", code: 12, userInfo: [NSLocalizedDescriptionKey: "Incomplete ICNS chunk set"])
    }
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

do {
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
    for (name, pixels) in variants {
        try drawIcon(pixels: pixels, destination: iconset.appendingPathComponent(name))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", "-o", temporaryOutput.path, iconset.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus != 0 {
        FileHandle.standardError.write(Data("iconutil could not pack this iconset; using the validated ICNS container fallback.\n".utf8))
        try writeFallbackICNS(iconset: iconset, output: temporaryOutput)
    }

    if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryOutput)
    } else {
        try fileManager.moveItem(at: temporaryOutput, to: destination)
    }
    print("Generated \(destination.path)")
} catch {
    FileHandle.standardError.write(Data("Icon generation failed: \(error)\n".utf8))
    exit(1)
}
