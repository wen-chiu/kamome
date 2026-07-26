import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// The stop group's placement rules, swept over every position a vehicle can
/// occupy in a static frame (Chiu 2026-07-25).
///
/// This is the regression net for a whole *class* of bug rather than one stop on
/// one trip: while the camera dollied into each stop, the vehicle was guaranteed
/// centred and any frame-centred overlay was safe. With the camera static that
/// assumption is gone, so these assert the two invariants directly — the group
/// never covers the vehicle, and never leaves the frame — at every anchor rather
/// than waiting for a collision to be spotted by eye in one rendered film.
final class RecapStopLayoutTests: XCTestCase {
    private let frame = CGSize(width: 1080, height: 1920)
    private let cardSize = CGSize(width: 540, height: 675)
    private let clearance: CGFloat = 240
    private let vehiclePx: CGFloat = 380
    private let margin: CGFloat = 48

    private func layout(anchor: CGPoint, cardSize: CGSize? = nil) -> RecapStopLayout {
        RecapStopLayout(
            anchor: anchor,
            cardSize: cardSize ?? self.cardSize,
            labelBandHeight: 250,
            labelBandWidth: 420,
            clearance: clearance,
            marginPx: margin,
            frameSize: frame
        )
    }

    /// Every anchor a vehicle could sit at, including the corners and edges a
    /// long trip in a fixed frame will genuinely produce.
    private var anchorSweep: [CGPoint] {
        stride(from: 0.0, through: 1.0, by: 0.1).flatMap { fractionX in
            stride(from: 0.0, through: 1.0, by: 0.1).map { fractionY in
                CGPoint(x: frame.width * fractionX, y: frame.height * fractionY)
            }
        }
    }

    /// The invariant that actually matters: the stop's **name** is never printed
    /// across the car. The card itself may cover it — it is opaque and it is the
    /// subject of the beat — but text over the vehicle is what looked broken.
    func testNameBandNeverCoversTheVehicleAnywhereInFrame() {
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor)
            XCTAssertFalse(
                placed.labelOverlaps(vehicleAt: anchor, lengthPx: vehiclePx),
                "name band overlaps the vehicle at \(anchor)"
            )
        }
    }

    func testCardAndNameBandStayInsideTheFrameAnywhereInFrame() {
        let bounds = CGRect(origin: .zero, size: frame)
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor)
            XCTAssertTrue(bounds.contains(placed.cardRect), "card leaves the frame at \(anchor)")
            XCTAssertTrue(bounds.contains(placed.labelRect), "name band leaves the frame at \(anchor)")
        }
    }

    /// The name band always ends up on the side of the card facing away from the
    /// vehicle — that is what keeps it off the car when the card cannot clear it.
    func testNameBandSitsOnTheFarSideOfTheCardFromTheVehicle() {
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor)
            if placed.labelIsAboveCard {
                XCTAssertGreaterThanOrEqual(placed.labelRect.minY, placed.cardRect.maxY - 0.5, "\(anchor)")
            } else {
                XCTAssertLessThanOrEqual(placed.labelRect.maxY, placed.cardRect.minY + 0.5, "\(anchor)")
            }
        }
    }

    /// The card prefers to sit above the vehicle, and flips below only when
    /// there is no room above — so a stop low in frame still reads naturally.
    func testCardSitsAboveTheVehicleWhenThereIsRoomAndFlipsBelowWhenNot() {
        let low = layout(anchor: CGPoint(x: frame.width / 2, y: 150))
        XCTAssertGreaterThan(low.cardRect.minY, 150, "with room above, the card goes above")

        let high = layout(anchor: CGPoint(x: frame.width / 2, y: frame.height - 150))
        XCTAssertLessThan(high.cardRect.maxY, frame.height - 150, "with no room above, it flips below")
    }

    /// The card tracks the vehicle horizontally rather than sitting frame-centred
    /// — that is the actual fix for the Bunbury collision.
    func testCardTracksTheVehicleHorizontally() {
        let left = layout(anchor: CGPoint(x: 400, y: frame.height / 2))
        let right = layout(anchor: CGPoint(x: 680, y: frame.height / 2))
        XCTAssertLessThan(left.cardRect.midX, right.cardRect.midX, "the card follows the vehicle across")
        XCTAssertEqual(left.cardRect.midX, 400, accuracy: 1, "centred on the vehicle when there is room")
    }

    /// A vehicle right at the frame edge still gets a fully visible card, clamped
    /// inward rather than half drawn off-screen.
    func testCardClampsInwardAtTheFrameEdges() {
        for anchorX in [0.0, frame.width] {
            let placed = layout(anchor: CGPoint(x: anchorX, y: frame.height / 2))
            XCTAssertGreaterThanOrEqual(placed.cardRect.minX, margin - 0.5, "clamped off the left edge")
            XCTAssertLessThanOrEqual(placed.cardRect.maxX, frame.width - margin + 0.5, "clamped off the right")
        }
    }

    /// Beat 1 has no card, so the name band is the whole group and must clear the
    /// vehicle outright — and still stay in frame for a stop near the edge.
    func testLeadInLabelClearsTheVehicleAndStaysInFrame() {
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor, cardSize: .zero)
            XCTAssertFalse(
                placed.labelOverlaps(vehicleAt: anchor, lengthPx: vehiclePx),
                "lead-in label overlaps the vehicle at \(anchor)"
            )
            XCTAssertTrue(
                CGRect(origin: .zero, size: frame).contains(placed.labelRect),
                "lead-in label leaves the frame at \(anchor)"
            )
        }
    }
}
