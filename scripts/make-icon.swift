#!/usr/bin/env swift
// Draws the MDReader app icon (rounded rect, blue gradient, white "M↓"
// markdown mark) at every required size and assembles packaging/AppIcon.icns
// via iconutil. Requires only Command Line Tools. Output is committed.
import AppKit

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixels)
    let inset = s * 0.055
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.26, blue: 0.68, alpha: 1),
        ])!
    gradient.draw(in: path, angle: -90)

    let font = NSFont.systemFont(ofSize: rect.height * 0.42, weight: .heavy)
    let text = NSAttributedString(
        string: "M↓",
        attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = text.size()
    text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))

    return rep.representation(using: .png, properties: [:])!
}

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let iconset = repoRoot.appendingPathComponent("packaging/AppIcon.iconset")
let output = repoRoot.appendingPathComponent("packaging/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try drawIcon(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("error: iconutil failed")
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print("wrote \(output.path)")
