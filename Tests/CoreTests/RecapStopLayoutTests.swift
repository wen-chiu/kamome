import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// The stop group's placement rules, swept over every position a stop can occupy
/// in a static frame.
///
/// This is the regression net for a whole *class* of bug rather than one stop on
/// one trip. The invariant it now protects is the product one (Chiu 2026-07-26):
/// **the pin marks the stop**. It used to be shoved clear of the car by a
/// pixel-sized clearance that, at a wide act framing, put it kilometres from the
/// place it was labelling; the car now parks and vanishes for the stop, so the
/// group belongs on the anchor. What remains is keeping it on screen.
final class RecapStopLayoutTests: XCTestCase {
    private let frame = CGSize(width: 1080, height: 1920)
    private let cardSize = CGSize(width: 540, height: 675)
    private let pinHeight: CGFloat = 48
    private let bandHeight: CGFloat = 110
    private let bandWidth: CGFloat = 420
    private let gap: CGFloat = 16
    private let margin: CGFloat = 48

    private func layout(anchor: CGPoint, cardSize: CGSize? = nil) -> RecapStopLayout {
        RecapStopLayout(
            anchor: anchor,
            cardSize: cardSize ?? self.cardSize,
            pinHeight: pinHeight,
            labelBandHeight: bandHeight,
            labelBandWidth: bandWidth,
            gap: gap,
            marginPx: margin,
            frameSize: frame
        )
    }

    /// Every anchor a stop could sit at, including the corners and edges a long
    /// trip in a fixed frame will genuinely produce.
    private var anchorSweep: [CGPoint] {
        stride(from: 0.0, through: 1.0, by: 0.1).flatMap { fractionX in
            stride(from: 0.0, through: 1.0, by: 0.1).map { fractionY in
                CGPoint(x: frame.width * fractionX, y: frame.height * fractionY)
            }
        }
    }

    /// The invariant that matters now: a stop comfortably inside the frame gets
    /// its pin **exactly** on its own projected point, in both beats. Anything
    /// else is the film pointing at the wrong place.
    func testPinSitsExactlyOnTheStopWhenItIsInsideTheFrame() {
        for fractionX in stride(from: 0.25, through: 0.75, by: 0.05) {
            for fractionY in stride(from: 0.25, through: 0.75, by: 0.05) {
                let anchor = CGPoint(x: frame.width * fractionX, y: frame.height * fractionY)
                for size in [cardSize, CGSize.zero] {
                    let placed = layout(anchor: anchor, cardSize: size)
                    XCTAssertEqual(placed.pinPoint.x, anchor.x, accuracy: 0.5, "pin drifted in x at \(anchor)")
                    XCTAssertEqual(placed.pinPoint.y, anchor.y, accuracy: 0.5, "pin drifted in y at \(anchor)")
                }
            }
        }
    }

    /// A stop against the frame edge is nudged inward only as far as visibility
    /// demands — off-screen is worse than slightly off-place.
    func testPinIsNudgedInOnlyAtTheEdgesAndNeverLeavesTheFrame() {
        let bounds = CGRect(origin: .zero, size: frame)
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor)
            XCTAssertTrue(bounds.contains(placed.pinPoint), "pin left the frame at \(anchor)")
            XCTAssertLessThanOrEqual(
                abs(placed.pinPoint.x - anchor.x), margin + bandWidth / 2 + 0.5,
                "pin moved further than the margin required at \(anchor)"
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

    /// When the cluster hangs above the pin — the preferred side — reading upward
    /// is point → place → photos, so the name stands on the pin.
    func testNameStandsOnThePinWheneverTheClusterOpensUpward() {
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor)
            guard placed.cardIsAbovePin else { continue }
            XCTAssertGreaterThanOrEqual(
                placed.labelRect.minY, placed.pinPoint.y - 0.5, "the name fell below its pin at \(anchor)"
            )
        }
    }

    /// The load-bearing composition rule (2026-07-31): the name is the *caption of
    /// the photograph*, so the card sits directly on the name band with only the
    /// gap between them — **everywhere in frame**, on either side of the pin.
    ///
    /// This is the regression net for the bug the prototype port surfaced: the
    /// card alone used to flip below the pin while its own name stayed above,
    /// splitting one composition across half the frame.
    func testTheCardAndItsNameStayOneContiguousCluster() {
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor)
            XCTAssertEqual(
                placed.cardRect.minY - placed.labelRect.maxY, gap, accuracy: 0.5,
                "photo and its caption drifted apart at \(anchor)"
            )
        }
    }

    /// The cluster prefers to open above the pin and mirrors below only when there
    /// is no room — so a stop high in frame still reads, as one group.
    func testClusterOpensAboveThePinAndMirrorsBelowWhenThereIsNoRoom() {
        let low = layout(anchor: CGPoint(x: frame.width / 2, y: 300))
        XCTAssertTrue(low.cardIsAbovePin)
        XCTAssertGreaterThan(low.cardRect.minY, low.labelRect.minY, "with room above, the card opens above")

        let high = layout(anchor: CGPoint(x: frame.width / 2, y: frame.height - 200))
        XCTAssertFalse(high.cardIsAbovePin)
        XCTAssertLessThan(high.cardRect.maxY, high.pinPoint.y, "with no room above, the group mirrors below")
        XCTAssertLessThan(high.labelRect.maxY, high.cardRect.minY + 0.5, "and the name follows its photo down")
    }

    /// The card tracks the stop horizontally rather than sitting frame-centred.
    func testCardTracksTheStopHorizontally() {
        let left = layout(anchor: CGPoint(x: 400, y: frame.height / 2))
        let right = layout(anchor: CGPoint(x: 680, y: frame.height / 2))
        XCTAssertLessThan(left.cardRect.midX, right.cardRect.midX, "the card follows the stop across")
        XCTAssertEqual(left.cardRect.midX, 400, accuracy: 1, "centred on the stop when there is room")
    }

    /// A stop right at the frame edge still gets a fully visible card, clamped
    /// inward rather than half drawn off-screen.
    func testCardClampsInwardAtTheFrameEdges() {
        for anchorX in [0.0, frame.width] {
            let placed = layout(anchor: CGPoint(x: anchorX, y: frame.height / 2))
            XCTAssertGreaterThanOrEqual(placed.cardRect.minX, margin - 0.5, "clamped off the left edge")
            XCTAssertLessThanOrEqual(placed.cardRect.maxX, frame.width - margin + 0.5, "clamped off the right")
        }
    }

    /// Beat 1 has no card, so the pin + name is the whole group.
    func testLeadInGroupIsJustThePinAndNameAndStaysInFrame() {
        for anchor in anchorSweep {
            let placed = layout(anchor: anchor, cardSize: .zero)
            XCTAssertEqual(placed.cardRect.width, 0)
            XCTAssertEqual(placed.cardRect.height, 0)
            XCTAssertTrue(
                CGRect(origin: .zero, size: frame).contains(placed.labelRect),
                "lead-in label leaves the frame at \(anchor)"
            )
        }
    }
}
