#!/usr/bin/env swift
import AppKit

// MARK: - Icon Design: Shield + Camera Lens

func generateIcon(pixels: Int) -> NSBitmapImageRep {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let ctx = NSGraphicsContext.current!.cgContext
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // ── 1. Background gradient (deep navy → rich blue → teal accent) ──
    let bgColors = [
        CGColor(colorSpace: colorSpace, components: [0.04, 0.06, 0.14, 1])!,
        CGColor(colorSpace: colorSpace, components: [0.08, 0.18, 0.35, 1])!,
        CGColor(colorSpace: colorSpace, components: [0.15, 0.38, 0.62, 1])!,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: s, y: s),
            options: [])
    }

    // ── 2. Subtle radial highlight in center ──
    let hlColors = [
        CGColor(colorSpace: colorSpace, components: [0.25, 0.50, 0.78, 0.25])!,
        CGColor(colorSpace: colorSpace, components: [0.25, 0.50, 0.78, 0.0])!,
    ] as CFArray
    if let hlGrad = CGGradient(colorsSpace: colorSpace, colors: hlColors, locations: [0, 1]) {
        ctx.drawRadialGradient(hlGrad,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.55),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.5, y: s * 0.55),
            endRadius: s * 0.45,
            options: [])
    }

    // ── 3. Shield shape ──
    let shieldW = s * 0.62
    let shieldH = s * 0.68
    let shieldCX = s / 2
    let shieldBottom = s * 0.10
    let shieldTop = shieldBottom + shieldH
    let shieldLeft = shieldCX - shieldW / 2
    let shieldRight = shieldCX + shieldW / 2
    let cornerR = shieldW * 0.12

    let shield = CGMutablePath()
    // Bottom point
    shield.move(to: CGPoint(x: shieldCX, y: shieldBottom))
    // Right side curve up
    shield.addCurve(to: CGPoint(x: shieldRight, y: shieldBottom + shieldH * 0.38),
        control1: CGPoint(x: shieldCX + shieldW * 0.22, y: shieldBottom + shieldH * 0.06),
        control2: CGPoint(x: shieldRight, y: shieldBottom + shieldH * 0.18))
    // Right side straight up
    shield.addLine(to: CGPoint(x: shieldRight, y: shieldTop - cornerR))
    // Top-right corner
    shield.addArc(center: CGPoint(x: shieldRight - cornerR, y: shieldTop - cornerR),
        radius: cornerR, startAngle: 0, endAngle: .pi / 2, clockwise: false)
    // Top edge
    shield.addLine(to: CGPoint(x: shieldLeft + cornerR, y: shieldTop))
    // Top-left corner
    shield.addArc(center: CGPoint(x: shieldLeft + cornerR, y: shieldTop - cornerR),
        radius: cornerR, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
    // Left side straight down
    shield.addLine(to: CGPoint(x: shieldLeft, y: shieldBottom + shieldH * 0.38))
    // Left side curve to bottom point
    shield.addCurve(to: CGPoint(x: shieldCX, y: shieldBottom),
        control1: CGPoint(x: shieldLeft, y: shieldBottom + shieldH * 0.18),
        control2: CGPoint(x: shieldCX - shieldW * 0.22, y: shieldBottom + shieldH * 0.06))
    shield.closeSubpath()

    // Shield drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.04,
        color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.5]))
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.97])!)
    ctx.addPath(shield)
    ctx.fillPath()
    ctx.restoreGState()

    // Shield gradient overlay (subtle top-to-bottom for depth)
    ctx.saveGState()
    ctx.addPath(shield)
    ctx.clip()
    let shieldColors = [
        CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!,
        CGColor(colorSpace: colorSpace, components: [0.90, 0.93, 0.96, 1])!,
    ] as CFArray
    if let sg = CGGradient(colorsSpace: colorSpace, colors: shieldColors, locations: [0, 1]) {
        ctx.drawLinearGradient(sg,
            start: CGPoint(x: s / 2, y: shieldTop),
            end: CGPoint(x: s / 2, y: shieldBottom),
            options: [])
    }
    ctx.restoreGState()

    // ── 4. Camera icon inside shield ──
    let camCenterY = shieldBottom + shieldH * 0.52
    let camCenterX = shieldCX

    // Camera body (rounded rect)
    let bodyW = shieldW * 0.52
    let bodyH = shieldH * 0.30
    let bodyRect = CGRect(
        x: camCenterX - bodyW / 2,
        y: camCenterY - bodyH / 2,
        width: bodyW, height: bodyH)
    let bodyPath = CGPath(roundedRect: bodyRect,
        cornerWidth: bodyH * 0.18, cornerHeight: bodyH * 0.18, transform: nil)

    // Camera viewfinder bump (trapezoid on top)
    let vfW = bodyW * 0.30
    let vfH = bodyH * 0.22
    let vfPath = CGMutablePath()
    let vfBottom = bodyRect.maxY
    vfPath.move(to: CGPoint(x: camCenterX - vfW * 0.6, y: vfBottom))
    vfPath.addLine(to: CGPoint(x: camCenterX - vfW * 0.4, y: vfBottom + vfH))
    vfPath.addLine(to: CGPoint(x: camCenterX + vfW * 0.4, y: vfBottom + vfH))
    vfPath.addLine(to: CGPoint(x: camCenterX + vfW * 0.6, y: vfBottom))
    vfPath.closeSubpath()

    // Draw camera body + viewfinder in dark blue
    let camColor = CGColor(colorSpace: colorSpace, components: [0.06, 0.12, 0.25, 1])!
    ctx.setFillColor(camColor)
    ctx.addPath(bodyPath)
    ctx.fillPath()
    ctx.addPath(vfPath)
    ctx.fillPath()

    // Lens — outer ring
    let lensR = min(bodyW, bodyH) * 0.38
    let lensRect = CGRect(x: camCenterX - lensR, y: camCenterY - lensR,
                          width: lensR * 2, height: lensR * 2)
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.15, 0.35, 0.58, 1])!)
    ctx.fillEllipse(in: lensRect)

    // Lens — mid ring
    let midR = lensR * 0.72
    let midRect = CGRect(x: camCenterX - midR, y: camCenterY - midR,
                         width: midR * 2, height: midR * 2)
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.10, 0.22, 0.42, 1])!)
    ctx.fillEllipse(in: midRect)

    // Lens — inner bright ring (aperture)
    let innerR = lensR * 0.45
    let innerRect = CGRect(x: camCenterX - innerR, y: camCenterY - innerR,
                           width: innerR * 2, height: innerR * 2)
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.30, 0.60, 0.85, 1])!)
    ctx.fillEllipse(in: innerRect)

    // Lens — highlight dot (glass reflection)
    let dotR = lensR * 0.16
    let dotX = camCenterX + lensR * 0.20
    let dotY = camCenterY + lensR * 0.20
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.85])!)
    ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR,
                               width: dotR * 2, height: dotR * 2))

    // Small decorative dot (second reflection)
    let dot2R = dotR * 0.45
    let dot2X = camCenterX - lensR * 0.12
    let dot2Y = camCenterY - lensR * 0.25
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.4])!)
    ctx.fillEllipse(in: CGRect(x: dot2X - dot2R, y: dot2Y - dot2R,
                               width: dot2R * 2, height: dot2R * 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Generate .iconset

let iconsetPath = "Guard.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let rep = generateIcon(pixels: entry.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(entry.name)")
        continue
    }
    let path = "\(iconsetPath)/\(entry.name).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("  \(entry.name).png  (\(entry.pixels)x\(entry.pixels))")
}

print("Done. Run: iconutil --convert icns \(iconsetPath)")
