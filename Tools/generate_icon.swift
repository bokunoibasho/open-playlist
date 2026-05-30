#!/usr/bin/env swift
//
// generate_icon.swift — renders the Open Playlist app icon (1024×1024 PNG).
//
// Reproducible icon generation (Phase 8 / #4): an accent-pink gradient field
// with a white `music.note` SF Symbol. Run from the repo root:
//
//   xcrun swift Tools/generate_icon.swift
//
// Writes App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.
// Keep the accent in step with App/Assets.xcassets/AccentColor.colorset.

import AppKit

let side = 1024

let outputURL = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

// White-tinted copy of a template image (SF Symbols draw black by default).
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    color.set()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    rect.fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

// RGBA backing: CGBitmapContext requires an alpha channel for RGB, so we draw
// into RGBA. The gradient covers the whole canvas, so every pixel is fully
// opaque — the resulting icon has no see-through areas.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Diagonal accent gradient (top-left bright → bottom-right deep).
let colors = [
    NSColor(srgbRed: 1.00, green: 0.27, blue: 0.45, alpha: 1).cgColor,
    NSColor(srgbRed: 0.74, green: 0.10, blue: 0.38, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: colors,
    locations: [0, 1]
)!
let s = CGFloat(side)
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: s, y: 0),
    options: []
)

// Centered white music-note glyph.
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)
if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let note = tinted(symbol, .white)
    let noteSize = note.size
    let origin = NSPoint(x: (s - noteSize.width) / 2, y: (s - noteSize.height) / 2)
    note.draw(
        in: NSRect(origin: origin, size: noteSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
} else {
    fatalError("Could not load SF Symbol music.note")
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: outputURL)
print("Wrote \(outputURL.path) (\(side)×\(side))")
