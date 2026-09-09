#!/usr/bin/env swift
//
// generate-app-icon.swift
//
// Rasterizes Zenith's brand mark — two overlapping triangular "peaks"
// on a brand-blue rounded square — into every PNG size required by
// `AppIcon.appiconset/Contents.json`, plus a `.iconset` folder ready
// for `iconutil -c icns` (used as the DMG volume icon; see
// docs/build-and-package.md).
//
// The peak geometry mirrors `Zenith/UI/Support/ZenithMark.swift`
// by hand — if you change one, change the other.
//
// Usage (from the repo root):
//   swift Scripts/generate-app-icon.swift
//   iconutil -c icns branding/zenith.iconset -o branding/zenith.icns
//
// Pure Core Graphics / ImageIO — no AppKit, no extra dependencies.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry (normalized 0...1, origin top-left, matches ZenithMark.swift)

let backPeak: [CGPoint] = [
    CGPoint(x: 0.21875, y: 0.71875),
    CGPoint(x: 0.40625, y: 0.3125),
    CGPoint(x: 0.59375, y: 0.71875),
]
let frontPeak: [CGPoint] = [
    CGPoint(x: 0.375, y: 0.75),
    CGPoint(x: 0.53125, y: 0.21875),
    CGPoint(x: 0.75, y: 0.75),
]

/// Zenith brand blue, `#326bff`.
let brandBlue = CGColor(red: 0x32 / 255.0, green: 0x6b / 255.0, blue: 0xff / 255.0, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)

/// Apple's mac app-icon corner radius is ~18.11% of the canvas
/// (185.4/1024pt on the official template).
let cornerRadiusFraction: CGFloat = 185.4 / 1024

func renderIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create CGContext for size \(pixels)")
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * cornerRadiusFraction
    context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.setFillColor(brandBlue)
    context.fillPath()

    func fillTriangle(_ points: [CGPoint], color: CGColor, alpha: CGFloat) {
        // CG's origin is bottom-left; our coordinates are authored
        // top-down (matching SVG/SwiftUI), so flip Y.
        let flipped = points.map { CGPoint(x: $0.x * size, y: (1 - $0.y) * size) }
        context.beginPath()
        context.move(to: flipped[0])
        context.addLine(to: flipped[1])
        context.addLine(to: flipped[2])
        context.closePath()
        context.setAlpha(alpha)
        context.setFillColor(color)
        context.fillPath()
    }

    fillTriangle(backPeak, color: white, alpha: 0.45)
    fillTriangle(frontPeak, color: white, alpha: 1)

    guard let image = context.makeImage() else {
        fatalError("Could not render image for size \(pixels)")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not create PNG destination at \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not finalize PNG at \(url.path)")
    }
}

// MARK: - Output locations

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent() // Scripts/ -> repo root
let appIconDir = repoRoot.appendingPathComponent("Zenith/Assets.xcassets/AppIcon.appiconset")
let brandingDir = repoRoot.appendingPathComponent("branding")
let iconsetDir = brandingDir.appendingPathComponent("zenith.iconset")

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// (point size, scale) -> pixel size, named per both Xcode's
// AppIcon.appiconset convention and Apple's .iconset convention for
// `iconutil` — they're identical, so one render feeds both.
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (points, scale) in sizes {
    let pixels = points * scale
    let filename = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    let image = renderIcon(pixels: pixels)
    writePNG(image, to: appIconDir.appendingPathComponent(filename))
    writePNG(image, to: iconsetDir.appendingPathComponent(filename))
}

print("Wrote \(sizes.count) PNGs to:")
print("  \(appIconDir.path)")
print("  \(iconsetDir.path)")
print("Next: iconutil -c icns \(iconsetDir.path) -o \(brandingDir.appendingPathComponent("zenith.icns").path)")
