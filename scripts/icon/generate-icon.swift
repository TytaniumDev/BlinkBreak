#!/usr/bin/env swift
//
// generate-icon.swift
//
// Generates a 1024x1024 PNG app-icon placeholder for BlinkBreak. Uses only
// CoreGraphics + CoreText so it works as a plain `swift script.swift` run
// with no AppKit dependency. Run with:
//
//     swift scripts/icon/generate-icon.swift <output.png>
//
// Produces a calm dark-teal gradient matching the in-app CalmBackground,
// a subtle blue accent ring, and a large white "BB" monogram in the center.
//

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: swift generate-icon.swift <output.png>\n", stderr)
    exit(1)
}
let outputPath = CommandLine.arguments[1]
let size: Int = 1024

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("failed to create CGContext\n", stderr)
    exit(2)
}

// Background gradient (calm dark teal).
let topColor = CGColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1.0)
let bottomColor = CGColor(red: 0.02, green: 0.10, blue: 0.12, alpha: 1.0)
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [topColor, bottomColor] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Subtle accent ring.
let ringColor = CGColor(red: 0.18, green: 0.43, blue: 0.95, alpha: 0.35)
ctx.setStrokeColor(ringColor)
ctx.setLineWidth(16)
let ringInset: CGFloat = 140
ctx.strokeEllipse(in: CGRect(
    x: ringInset, y: ringInset,
    width: CGFloat(size) - ringInset * 2, height: CGFloat(size) - ringInset * 2
))

// "BB" monogram via CoreText (using raw CFString attribute keys so the
// script doesn't need AppKit / UIKit).
let text = "BB" as CFString
let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 440, nil)
let whiteColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

let attrs: [CFString: Any] = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: whiteColor
]
let attributed = CFAttributedStringCreate(nil, text, attrs as CFDictionary)!
let line = CTLineCreateWithAttributedString(attributed)
let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
let textX = (CGFloat(size) - bounds.width) / 2 - bounds.origin.x
let textY = (CGFloat(size) - bounds.height) / 2 - bounds.origin.y
ctx.textPosition = CGPoint(x: textX, y: textY)
CTLineDraw(line, ctx)

// Export as PNG.
guard let cgImage = ctx.makeImage() else {
    fputs("failed to makeImage\n", stderr)
    exit(3)
}
let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1, nil
) else {
    fputs("failed to create destination\n", stderr)
    exit(4)
}
CGImageDestinationAddImage(dest, cgImage, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(outputPath)")
} else {
    fputs("failed to finalize PNG\n", stderr)
    exit(5)
}
