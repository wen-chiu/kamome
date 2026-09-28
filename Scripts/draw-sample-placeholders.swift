#!/usr/bin/env swift
// Draws the PLACEHOLDER illustrations for Kamome's sample trip.
//
//     swift Scripts/draw-sample-placeholders.swift App/Resources/SampleTrip
//
// These are stand-ins so the sample works end to end. The real ones are
// Kamome hand-drawn illustrations (Chiu 2026-09-28), tracked as a `chiu` issue.
// When they exist, drop them in with the same file names and delete this
// script. Deterministic: the same input draws the same pixels.
import AppKit
import CoreGraphics
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let width = 900, height = 1200

struct Scene {
    let name: String
    let sky: (CGColor, CGColor)
    let sea: CGColor
    let land: CGColor
    let accent: CGColor
    let motif: Motif
}

enum Motif { case pebbles, terraces, bridge, hills, lanterns }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: alpha
    )
}

// Soft, muted — the emotional layer's palette (CHARTER.md §7).
let scenes: [Scene] = [
    Scene(name: "qixingtan", sky: (rgb(0xCFE6EC), rgb(0xF6EEDD)), sea: rgb(0x7FB6C4), land: rgb(0xD9D2C3), accent: rgb(0x9AA3A8), motif: .pebbles),
    Scene(name: "shitiping", sky: (rgb(0xD7E8E4), rgb(0xFBF3E4)), sea: rgb(0x6FA7B5), land: rgb(0xC9C1AE), accent: rgb(0xA89F8B), motif: .terraces),
    Scene(name: "sanxiantai", sky: (rgb(0xF4D9C6), rgb(0xFBEFE2)), sea: rgb(0x78AFC0), land: rgb(0xB9C7A5), accent: rgb(0xD98C6A), motif: .bridge),
    Scene(name: "dulan", sky: (rgb(0xDCE7D5), rgb(0xFAF4E6)), sea: rgb(0x86B8C2), land: rgb(0x9DB88E), accent: rgb(0x7E9C74), motif: .hills),
    Scene(name: "tiehua", sky: (rgb(0x3E4A6B), rgb(0xE9B99A)), sea: rgb(0x4C6A86), land: rgb(0x5B6B5A), accent: rgb(0xF2C46D), motif: .lanterns)
]

/// A cheap pseudo-random stream, so a wobble is the same on every run.
struct Wobble {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 1000) / 1000 - 0.5
    }
}

func draw(_ scene: Scene, variant: Int) -> CGImage? {
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    var wobble = Wobble(state: scene.name.unicodeScalars.reduce(UInt64(17)) { $0 &* 31 &+ UInt64($1.value) } &+ UInt64(variant) &* 977)
    let w = CGFloat(width), h = CGFloat(height)

    // Sky.
    let gradient = CGGradient(colorsSpace: nil, colors: [scene.sky.0, scene.sky.1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.35), options: [.drawsAfterEndLocation])

    // Sun or moon.
    ctx.setFillColor(scene.motif == .lanterns ? rgb(0xF7E7C6) : rgb(0xFFF6E0, 0.9))
    let sunX = variant == 1 ? w * 0.72 : w * 0.3
    ctx.fillEllipse(in: CGRect(x: sunX - 70, y: h * 0.74 - 70, width: 140, height: 140))

    // Sea: a band with a wavy top edge.
    let horizon = h * (variant == 1 ? 0.5 : 0.56)
    ctx.setFillColor(scene.sea)
    let sea = CGMutablePath()
    sea.move(to: CGPoint(x: 0, y: 0))
    sea.addLine(to: CGPoint(x: 0, y: horizon))
    var x: CGFloat = 0
    while x <= w {
        sea.addLine(to: CGPoint(x: x, y: horizon + wobble.next() * 6))
        x += 30
    }
    sea.addLine(to: CGPoint(x: w, y: 0))
    sea.closeSubpath()
    ctx.addPath(sea)
    ctx.fillPath()

    // Wave strokes, slightly uneven — line art, not vector-perfect.
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.55))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    for row in 0..<5 {
        let y = horizon - 60 - CGFloat(row) * 70
        let x0 = 80 + wobble.next() * 120 + CGFloat(row % 2) * 200
        ctx.move(to: CGPoint(x: x0, y: y))
        ctx.addCurve(
            to: CGPoint(x: x0 + 160, y: y + wobble.next() * 8),
            control1: CGPoint(x: x0 + 50, y: y + 18), control2: CGPoint(x: x0 + 110, y: y - 18)
        )
        ctx.strokePath()
    }

    // Land and the stop's motif, in the foreground.
    ctx.setFillColor(scene.land)
    let land = CGMutablePath()
    land.move(to: CGPoint(x: 0, y: 0))
    land.addLine(to: CGPoint(x: 0, y: h * 0.22))
    land.addQuadCurve(to: CGPoint(x: w, y: h * 0.16), control: CGPoint(x: w * 0.5, y: h * (0.3 + wobble.next() * 0.04)))
    land.addLine(to: CGPoint(x: w, y: 0))
    land.closeSubpath()
    ctx.addPath(land)
    ctx.fillPath()

    ctx.setFillColor(scene.accent)
    ctx.setStrokeColor(scene.accent)
    switch scene.motif {
    case .pebbles:
        for i in 0..<14 {
            let px = CGFloat(i) * 66 + 20 + wobble.next() * 20
            let py = h * 0.1 + wobble.next() * 90
            ctx.fillEllipse(in: CGRect(x: px, y: py, width: 44 + wobble.next() * 16, height: 26 + wobble.next() * 8))
        }
    case .terraces:
        for i in 0..<4 {
            let y = h * 0.05 + CGFloat(i) * 55
            ctx.fill(CGRect(x: CGFloat(i) * 60, y: y, width: w * 0.55 - CGFloat(i) * 40, height: 38))
        }
    case .bridge:
        ctx.setLineWidth(14)
        let deck = horizon - 90
        ctx.move(to: CGPoint(x: 40, y: deck))
        ctx.addLine(to: CGPoint(x: w - 40, y: deck))
        ctx.strokePath()
        let arches = 8
        let span = (w - 80) / CGFloat(arches)
        ctx.setLineWidth(8)
        for i in 0..<arches {
            let x0 = 40 + CGFloat(i) * span
            ctx.move(to: CGPoint(x: x0, y: deck))
            ctx.addQuadCurve(to: CGPoint(x: x0 + span, y: deck), control: CGPoint(x: x0 + span / 2, y: deck + 110))
            ctx.strokePath()
        }
    case .hills:
        ctx.setFillColor(scene.accent)
        let hills = CGMutablePath()
        hills.move(to: CGPoint(x: 0, y: horizon))
        hills.addQuadCurve(to: CGPoint(x: w * 0.55, y: horizon), control: CGPoint(x: w * 0.25, y: horizon + 260))
        hills.addQuadCurve(to: CGPoint(x: w, y: horizon), control: CGPoint(x: w * 0.8, y: horizon + 180))
        hills.closeSubpath()
        ctx.addPath(hills)
        ctx.fillPath()
    case .lanterns:
        ctx.setLineWidth(3)
        ctx.setStrokeColor(rgb(0xF2E3C4, 0.8))
        let lineY = h * 0.7
        ctx.move(to: CGPoint(x: 0, y: lineY + 40))
        ctx.addQuadCurve(to: CGPoint(x: w, y: lineY + 40), control: CGPoint(x: w / 2, y: lineY - 40))
        ctx.strokePath()
        for i in 0..<7 {
            let t = CGFloat(i + 1) / 8
            let lx = w * t
            let ly = lineY + 40 - 80 * t * (1 - t) * 2 - 60
            ctx.setFillColor(scene.accent)
            ctx.fillEllipse(in: CGRect(x: lx - 26, y: ly - 34 + wobble.next() * 6, width: 52, height: 68))
        }
    }

    // A kamome (seagull) — two strokes, the brand's simplest mark.
    ctx.setStrokeColor(rgb(0x3B4A55, scene.motif == .lanterns ? 0.0 : 0.75))
    ctx.setLineWidth(6)
    let gx = variant == 1 ? w * 0.3 : w * 0.66, gy = h * 0.84
    ctx.move(to: CGPoint(x: gx - 50, y: gy))
    ctx.addQuadCurve(to: CGPoint(x: gx, y: gy - 6), control: CGPoint(x: gx - 25, y: gy + 30))
    ctx.addQuadCurve(to: CGPoint(x: gx + 50, y: gy), control: CGPoint(x: gx + 25, y: gy + 30))
    ctx.strokePath()

    return ctx.makeImage()
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for scene in scenes {
    for variant in 1...2 {
        guard let image = draw(scene, variant: variant) else { fatalError("could not draw \(scene.name)") }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
        let url = outDir.appendingPathComponent("sample-\(scene.name)-\(variant).png")
        try png.write(to: url)
        print(url.lastPathComponent)
    }
}
