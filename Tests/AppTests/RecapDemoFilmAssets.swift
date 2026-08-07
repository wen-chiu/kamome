import CoreGraphics
import CoreText
import XCTest

/// A stand-in photo: a diagonal gradient with a big index, so each deck slot
/// is visibly a different picture.
///
/// Split out of `RecapDemoFilmTests` (lint length only, Chiu 2026-08-07) — it
/// never used `self`, so the move needed no access changes.
func photoTile(index: Int) throws -> CGImage {
    let side = 900
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let palettes: [(CGColor, CGColor)] = [
        (CGColor(srgbRed: 0.20, green: 0.45, blue: 0.70, alpha: 1),
         CGColor(srgbRed: 0.10, green: 0.22, blue: 0.35, alpha: 1)),
        (CGColor(srgbRed: 0.75, green: 0.45, blue: 0.30, alpha: 1),
         CGColor(srgbRed: 0.38, green: 0.22, blue: 0.15, alpha: 1)),
        (CGColor(srgbRed: 0.35, green: 0.60, blue: 0.40, alpha: 1),
         CGColor(srgbRed: 0.18, green: 0.30, blue: 0.20, alpha: 1))
    ]
    let (top, bottom) = palettes[index % palettes.count]
    let gradient = try XCTUnwrap(CGGradient(
        colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]
    ))
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 300, nil)
    let attrs = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
    ] as CFDictionary
    let line = CTLineCreateWithAttributedString(
        CFAttributedStringCreate(kCFAllocatorDefault, "\(index + 1)" as CFString, attrs)!
    )
    let bounds = CTLineGetImageBounds(line, context)
    context.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2, y: (CGFloat(side) - bounds.height) / 2)
    CTLineDraw(line, context)
    return try XCTUnwrap(context.makeImage())
}
