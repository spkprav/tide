#!/usr/bin/env swift
import AppKit
import Foundation

let args = CommandLine.arguments
let svgPath = args.count > 1 ? args[1] : "assets/icon.svg"
let outDir  = args.count > 2 ? args[2] : "Tide.iconset"

let svgURL = URL(fileURLWithPath: svgPath)
guard FileManager.default.fileExists(atPath: svgURL.path) else {
    FileHandle.standardError.write("missing svg: \(svgURL.path)\n".data(using: .utf8)!)
    exit(1)
}

guard let image = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write("NSImage failed to read SVG\n".data(using: .utf8)!)
    exit(2)
}
image.size = NSSize(width: 1024, height: 1024)

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let targets: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixels, name) in targets {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else { continue }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero,
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let outURL = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    do {
        try data.write(to: outURL, options: .atomic)
        print("wrote \(name)  (\(pixels)x\(pixels))")
    } catch {
        FileHandle.standardError.write("write fail \(name): \(error)\n".data(using: .utf8)!)
    }
}
