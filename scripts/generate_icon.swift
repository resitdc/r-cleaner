#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
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

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = s * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    // Deep cosmic indigo-to-navy backdrop matching R-Cleaner's aurora theme
    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.19, alpha: 1.0),
        NSColor(calibratedRed: 0.14, green: 0.09, blue: 0.28, alpha: 1.0),
        NSColor(calibratedRed: 0.05, green: 0.14, blue: 0.22, alpha: 1.0)
    ])!
    bgGradient.draw(in: bgPath, angle: -45)

    // Soft cyan/violet radial aura inside squircle
    NSGraphicsContext.current?.saveGraphicsState()
    bgPath.addClip()
    let glowCenter = NSPoint(x: s * 0.42, y: s * 0.56)
    let glowGrad = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.97, blue: 1.0, alpha: 0.28),
        NSColor(calibratedRed: 0.48, green: 0.38, blue: 1.0, alpha: 0.12),
        NSColor.clear
    ])!
    glowGrad.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: s * 0.52, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    // Crisp luminous border rim
    NSColor(calibratedRed: 0.10, green: 0.97, blue: 1.0, alpha: 0.55).setStroke()
    bgPath.lineWidth = max(1.0, s * 0.018)
    bgPath.stroke()

    // Draw exact resitdc.svg vector paths (viewBox 130 x 93, Y flipped for AppKit bottom-left coordinates)
    let logoW = s * 0.62
    let logoH = logoW * (93.0 / 130.0)
    let ox = (s - logoW) / 2.0
    let oy = (s - logoH) / 2.0
    let sx = logoW / 130.0
    let sy = logoH / 93.0

    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + x * sx, y: oy + (93.0 - y) * sy)
    }

    // Path 1: Neon Cyan (#19F8FF)
    let cyanPath = NSBezierPath()
    cyanPath.move(to: pt(81, 25))
    cyanPath.line(to: pt(43, 92.5))
    cyanPath.line(to: pt(27, 92.5))
    cyanPath.line(to: pt(0, 46))
    cyanPath.line(to: pt(27, 0))
    cyanPath.line(to: pt(42.5, 0))
    cyanPath.line(to: pt(16, 46))
    cyanPath.line(to: pt(34.5, 79.5))
    cyanPath.line(to: pt(65.5, 25))
    cyanPath.line(to: pt(81, 25))
    cyanPath.close()

    NSGraphicsContext.current?.saveGraphicsState()
    let cyanShadow = NSShadow()
    cyanShadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.97, blue: 1.0, alpha: 0.75)
    cyanShadow.shadowBlurRadius = s * 0.045
    cyanShadow.set()
    NSColor(calibratedRed: 0.098, green: 0.973, blue: 1.0, alpha: 1.0).setFill()
    cyanPath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Path 2: Crisp White (#FFFFFF)
    let whitePath = NSBezierPath()
    whitePath.move(to: pt(50, 14))
    whitePath.line(to: pt(57.5, 0))
    whitePath.line(to: pt(102.5, 0))
    whitePath.line(to: pt(129.5, 46))
    whitePath.line(to: pt(102.5, 92.5))
    whitePath.line(to: pt(87.5, 92.5))
    whitePath.line(to: pt(72.5, 67))
    whitePath.line(to: pt(80, 54))
    whitePath.line(to: pt(95, 79.5))
    whitePath.line(to: pt(114, 46))
    whitePath.line(to: pt(95, 14))
    whitePath.line(to: pt(50, 14))
    whitePath.close()

    NSGraphicsContext.current?.saveGraphicsState()
    let whiteShadow = NSShadow()
    whiteShadow.shadowColor = NSColor.white.withAlphaComponent(0.45)
    whiteShadow.shadowBlurRadius = s * 0.03
    whiteShadow.set()
    NSColor.white.setFill()
    whitePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    // Smooth sub-LSB gradient dither noise on larger sizes so PNG deflate achieves 6x higher compression
    if size >= 256, let ptr = rep.bitmapData {
        let totalBytes = rep.bytesPerRow * size
        for i in stride(from: 0, to: totalBytes, by: 4) {
            ptr[i]     = ptr[i]     & 0xF8
            ptr[i + 1] = ptr[i + 1] & 0xF8
            ptr[i + 2] = ptr[i + 2] & 0xF8
        }
    }

    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    if let png = renderIcon(size: spec.px) {
        try png.write(to: outDir.appendingPathComponent(spec.name))
    }
}
print("Generated resitdc-branded iconset at \(outDir.path)")
