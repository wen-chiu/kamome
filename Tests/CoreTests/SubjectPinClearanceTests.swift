import CoreGraphics
@testable import KamomeExportEngine
import XCTest

/// **Below the pin, not on it** (Chiu 2026-11-03): where the car is drawn when
/// it must clear a pin. The surface draws y-up, so below is a smaller y.
final class SubjectPinClearanceTests: XCTestCase {
    private let pin = CGPoint(x: 500, y: 900)
    private let reach: CGFloat = 174

    func testACarOnThePinIsDrawnStraightBelowItsRing() {
        let drawn = VehicleSubjectRenderer.clearing(pin, of: pin, reachPx: reach, amount: 1)
        XCTAssertEqual(drawn.x, pin.x, accuracy: 1e-9)
        XCTAssertEqual(drawn.y, pin.y - reach, accuracy: 1e-9)
    }

    func testNothingMovesWithoutAPinOrAnAmountOrWhenFarAway() {
        let car = CGPoint(x: 520, y: 880)
        XCTAssertEqual(VehicleSubjectRenderer.clearing(car, of: nil, reachPx: reach, amount: 1), car)
        XCTAssertEqual(VehicleSubjectRenderer.clearing(car, of: pin, reachPx: reach, amount: 0), car)
        let far = CGPoint(x: pin.x + reach * 2, y: pin.y)
        XCTAssertEqual(VehicleSubjectRenderer.clearing(far, of: pin, reachPx: reach, amount: 1), far)
    }

    /// Driving off, the car eases back onto its road: no step between two
    /// positions one pixel apart, at any distance.
    func testTheCarSlidesBackRatherThanJumping() {
        var previous = VehicleSubjectRenderer.clearing(pin, of: pin, reachPx: reach, amount: 1)
        for step in 1...Int(reach * 1.5) {
            let car = CGPoint(x: pin.x + CGFloat(step), y: pin.y)
            let drawn = VehicleSubjectRenderer.clearing(car, of: pin, reachPx: reach, amount: 1)
            XCTAssertLessThan(hypot(drawn.x - previous.x, drawn.y - previous.y), 3, "jumped at \(step) px")
            previous = drawn
        }
    }

    /// The car is smaller than its canvas, so it steps clear by the art's own
    /// reach, not by half the canvas: a 100 px canvas whose ink starts 30 px
    /// down reaches 20 px above its centre.
    func testTheCarStepsClearByItsArtNotItsCanvas() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // y-up: rows 30–69 from the top are y 30…70 from the bottom.
        context.fill(CGRect(x: 20, y: 30, width: 60, height: 40))
        let car = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(VehicleSubjectRenderer.firstOpaqueRow(car), 30)
        XCTAssertEqual(VehicleSubjectRenderer.artTopPx(car, longestSidePx: 100), 20, accuracy: 1e-9)
        XCTAssertEqual(VehicleSubjectRenderer.artTopPx(car, longestSidePx: 300), 60, accuracy: 1e-9)
        XCTAssertEqual(VehicleSubjectRenderer.artTopPx(nil, longestSidePx: 300), 150, "the marker fills its box")
    }

    /// **A pin never hides the car** (Chiu 2026-11-03): the map's own marks
    /// draw under it, the photo deck and the HUD over it.
    func testPinsAndTownNamesDrawUnderTheCar() {
        let place = RecapCoordinate(lat: 0, lon: 0)
        XCTAssertTrue(FrameCompositor.drawsBelowSubject(.stopLabel(name: "A", coordinate: place, detail: nil, opacity: 1)))
        XCTAssertTrue(FrameCompositor.drawsBelowSubject(.placeNames([], opacity: 1)))
        XCTAssertTrue(FrameCompositor.drawsBelowSubject(.routeReveal([])))
        XCTAssertFalse(FrameCompositor.drawsBelowSubject(.hud(dayLabel: "", place: nil, travelledM: 0)))
        XCTAssertFalse(FrameCompositor.drawsBelowSubject(.mapCredit("")))
    }
}
