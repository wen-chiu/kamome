import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// **The day stamp, as drawn** (ADR 2026-10-28-a-new-day-presses-a-stamp-into-the-film):
/// the ink is the only day on screen while it is up, it presses where its style
/// says, and when it lands it is the HUD's own day — the hand-off has no seam.
final class RecapDayStampRenderTests: RecapRenderTestCase {
    private let frameWidth = 540
    private let frameHeight = 960
    private let ink = RGB(red: 0, green: 0, blue: 255)
    private let hudText = RGB(red: 0, green: 255, blue: 0)

    private struct NoPhotos: RecapPhotoResolving {
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
    }

    private func style(_ position: RecapDayStampStyle.Position = .underThePill) -> RecapStyle {
        var style = RecapStyle()
        style.hudTextColor = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        style.hudPillColor = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        style.dayStamp.inkColor = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        style.dayStamp.position = position
        return style
    }

    private func render(_ content: OverlayContent, style: RecapStyle) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
        let surface = RenderSurface(
            context: context, widthPx: frameWidth, heightPx: frameHeight, scale: CGFloat(frameWidth) / 1080
        ) { _, _ in .zero }
        let camera = CameraFrame(centerLat: 0, centerLon: 0, spanM: 1500, bearing: 0)
        RecapOverlayRenderer(style: style, resolver: NoPhotos()).render(content, camera: camera, into: surface)
        return try XCTUnwrap(context.makeImage())
    }

    private func stamping(clear: Double = 1, press: Double = 1, land: Double = 0, place: String? = nil) -> OverlayContent {
        .hud(
            dayLabel: "Day 2", place: place, travelledM: 0,
            dayStamp: RecapDayStamp(label: "Day 2", previousLabel: "Day 1", clear: clear, press: press, land: land)
        )
    }

    /// Where the pixels of one colour sit, as fractions of the frame (y down).
    private func centroid(_ image: CGImage, of target: RGB) throws -> (x: Double, y: Double)? {
        let (data, bytesPerRow) = try pixels(image)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var sum = (x: 0.0, y: 0.0, count: 0.0)
        for row in 0..<image.height {
            for col in 0..<image.width {
                let offset = row * bytesPerRow + col * 4
                if abs(Int(bytes[offset]) - target.red) <= 3, abs(Int(bytes[offset + 1]) - target.green) <= 3,
                   abs(Int(bytes[offset + 2]) - target.blue) <= 3 {
                    sum = (sum.x + Double(col), sum.y + Double(row), sum.count + 1)
                }
            }
        }
        guard sum.count >= 1 else { return nil }
        return (sum.x / sum.count / Double(image.width), sum.y / sum.count / Double(image.height))
    }

    func testWhileTheStampIsUpItIsTheOnlyDayOnScreen() throws {
        let plain = try render(.hud(dayLabel: "Day 2", place: nil, travelledM: 0), style: style())
        XCTAssertGreaterThan(try colorCount(plain, matching: hudText), 0, "the HUD sets its day")

        let pressed = try render(stamping(), style: style())
        XCTAssertEqual(try colorCount(pressed, matching: hudText), 0, "the pill's day slot is empty under the stamp")
        XCTAssertGreaterThan(try colorCount(pressed, matching: ink), 0, "and the stamp is in ink")

        let clearing = try render(stamping(clear: 0.5, press: 0), style: style())
        XCTAssertEqual(try colorCount(clearing, matching: ink), 0, "no ink while the day before is still fading")
    }

    func testTheStampPressesWhereItsStyleSays() throws {
        let under = try XCTUnwrap(centroid(try render(stamping(), style: style(.underThePill)), of: ink))
        XCTAssertLessThan(under.x, 0.4, "under the pill: at the frame's left, below the HUD")
        XCTAssertLessThan(under.y, 0.3)

        let centre = try XCTUnwrap(centroid(try render(stamping(), style: style(.upperCentre)), of: ink))
        XCTAssertEqual(centre.x, 0.5, accuracy: 0.08, "upper centre: centred")
        XCTAssertEqual(centre.y, 0.2, accuracy: 0.06, "in the upper band")
    }

    /// Landed, the stamp is the HUD's own type in the HUD's own place: the last
    /// frame of the stamp and the first frame without it are the same picture.
    func testALandedStampIsTheHUDsOwnDay() throws {
        for place in [nil, "Stop"] as [String?] {
            let landed = try render(stamping(land: 1, place: place), style: style())
            let hud = try render(.hud(dayLabel: "Day 2", place: place, travelledM: 0), style: style())
            let (lhs, bytesPerRow) = try pixels(landed)
            let rhs = try pixels(hud).data
            let left = try XCTUnwrap(CFDataGetBytePtr(lhs)), right = try XCTUnwrap(CFDataGetBytePtr(rhs))
            var visiblyDifferent = 0
            for offset in stride(from: 0, to: bytesPerRow * frameHeight, by: 4) {
                let diff = (0..<3).map { abs(Int(left[offset + $0]) - Int(right[offset + $0])) }.max() ?? 0
                if diff > 48 { visiblyDifferent += 1 }
            }
            XCTAssertLessThanOrEqual(visiblyDifferent, 12, "landed in \(place ?? "a pill with no place"): the seam shows")
        }
    }

    func testTheStampIsDrawnTheSameEveryTime() throws {
        for land in [0.0, 0.5] {
            let first = try render(stamping(press: 0.7, land: land), style: style())
            let second = try render(stamping(press: 0.7, land: land), style: style())
            XCTAssertEqual(try pixels(first).data as Data, try pixels(second).data as Data)
        }
    }
}
