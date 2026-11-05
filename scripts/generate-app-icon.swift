#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-app-icon.swift <output-icns-path>\n", stderr)
    exit(1)
}

let outputICNSPath = CommandLine.arguments[1]
let fileManager = FileManager.default
let tempIconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("SchoolTracker-\(UUID().uuidString).iconset", isDirectory: true)

try fileManager.createDirectory(at: tempIconsetURL, withIntermediateDirectories: true)
defer {
    try? fileManager.removeItem(at: tempIconsetURL)
}

func renderIcon(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context

    let s = CGFloat(pixelSize)
    let inset = s * 0.08
    let cardRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = cardRect.width * 0.225
    let squircle = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.34, alpha: 1.0),
        NSColor(calibratedRed: 0.16, green: 0.29, blue: 0.66, alpha: 1.0),
        NSColor(calibratedRed: 0.24, green: 0.51, blue: 0.94, alpha: 1.0)
    ])
    bgGradient?.draw(in: squircle, angle: -55)

    NSColor(calibratedWhite: 1.0, alpha: 0.20).setStroke()
    squircle.lineWidth = max(1.0, s * 0.015)
    squircle.stroke()

    // Calendar card silhouette in lower-right
    let calRect = NSRect(
        x: s * 0.25,
        y: s * 0.20,
        width: s * 0.50,
        height: s * 0.44
    )
    let calPath = NSBezierPath(roundedRect: calRect, xRadius: s * 0.06, yRadius: s * 0.06)
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
    calPath.fill()

    // Graduation cap mortarboard in upper center
    let centerX = s * 0.50
    let capCenterY = s * 0.62
    let capHalfW = s * 0.28
    let capHalfH = s * 0.13

    let mortarboard = NSBezierPath()
    mortarboard.move(to: NSPoint(x: centerX, y: capCenterY + capHalfH))
    mortarboard.line(to: NSPoint(x: centerX + capHalfW, y: capCenterY))
    mortarboard.line(to: NSPoint(x: centerX, y: capCenterY - capHalfH))
    mortarboard.line(to: NSPoint(x: centerX - capHalfW, y: capCenterY))
    mortarboard.close()
    NSColor.white.setFill()
    mortarboard.fill()

    // Tassel in warm gold
    let tassel = NSBezierPath()
    tassel.move(to: NSPoint(x: centerX + capHalfW * 0.55, y: capCenterY - capHalfH * 0.20))
    tassel.line(to: NSPoint(x: centerX + capHalfW * 0.72, y: capCenterY - capHalfH * 1.35))
    tassel.lineWidth = max(1.5, s * 0.022)
    NSColor(calibratedRed: 0.99, green: 0.78, blue: 0.24, alpha: 1.0).setStroke()
    tassel.stroke()

    // Checkmark / A+ grade badge in lower-right
    let badgeSize = s * 0.24
    let badgeRect = NSRect(x: s * 0.56, y: s * 0.18, width: badgeSize, height: badgeSize)
    let badgePath = NSBezierPath(ovalIn: badgeRect)
    NSColor(calibratedRed: 0.15, green: 0.78, blue: 0.52, alpha: 1.0).setFill()
    badgePath.fill()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: badgeRect.minX + badgeSize * 0.28, y: badgeRect.minY + badgeSize * 0.50))
    check.line(to: NSPoint(x: badgeRect.minX + badgeSize * 0.45, y: badgeRect.minY + badgeSize * 0.32))
    check.line(to: NSPoint(x: badgeRect.minX + badgeSize * 0.74, y: badgeRect.minY + badgeSize * 0.68))
    check.lineWidth = max(1.5, s * 0.028)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconSpecs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    guard let pngData = renderIcon(pixelSize: spec.pixels) else {
        fputs("[ERROR] Failed to render \(spec.name)\n", stderr)
        exit(1)
    }
    let destURL = tempIconsetURL.appendingPathComponent(spec.name)
    try pngData.write(to: destURL, options: .atomic)
}

let outputURL = URL(fileURLWithPath: outputICNSPath)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tempIconsetURL.path, "-o", outputURL.path]
try proc.run()
proc.waitUntilExit()

guard proc.terminationStatus == 0 else {
    fputs("[ERROR] iconutil failed with status \(proc.terminationStatus)\n", stderr)
    exit(proc.terminationStatus)
}
