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
}
