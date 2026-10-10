import CoreGraphics
@testable import Kamome
import KamomeExportEngine
import XCTest

/// **Two export leftovers** (#279): a killed render's file in tmp, and deck
/// photographs decoded smaller than the card they fill.
@MainActor
final class RecapExportLeftoversTests: XCTestCase {
    // MARK: - tmp

    /// A render ended by jetsam or a crash leaves its file; the next export
    /// removes it — and touches nothing else in tmp.
    func testTheNextExportSweepsWhatAKilledRenderLeft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leftovers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefix = RecapExportJob.renderFilePrefix
        for name in ["\(prefix)1.mp4", "\(prefix)2.gif", "someone-else.mp4", "notes.txt"] {
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent(name))
        }

        XCTAssertEqual(RecapExportJob.sweepLeftoverRenders(in: directory), 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(left, ["notes.txt", "someone-else.mp4"])
    }

    // MARK: - Deck photographs

    /// PhotoKit's aspect-fill: the photograph scaled to cover `target`.
    private func filled(_ photo: CGSize, into target: CGSize) -> CGSize {
        let scale = max(target.width / photo.width, target.height / photo.height)
        return CGSize(width: photo.width * scale, height: photo.height * scale)
    }

    /// **No photograph is upscaled into its card** (#279). Asked to fill the
    /// card itself, a portrait, a landscape and a panorama all arrive at least
    /// the card's size on both sides. Asked — as before — to fill a square of
    /// the card's width, the landscape arrived 1.31× too short.
    func testEveryPhotographArrivesAtLeastAsLargeAsTheCardItFills() {
        let style = RecapStyle.modernMinimal(.dark)
        let card = RecapExportJob.deckPhotoSize(frameWidthPx: 1080, style: style)
        XCTAssertEqual(card.height / card.width, style.deckPhotoAspect, accuracy: 0.01, "the card's own shape")

        for (name, photo) in [
            ("portrait", CGSize(width: 3024, height: 4032)), ("landscape", CGSize(width: 4032, height: 3024)),
            ("wide", CGSize(width: 4000, height: 2250)), ("panorama", CGSize(width: 8000, height: 2000))
        ] {
            let decoded = filled(photo, into: card)
            XCTAssertGreaterThanOrEqual(decoded.width, card.width - 0.5, "\(name) width")
            XCTAssertGreaterThanOrEqual(decoded.height, card.height - 0.5, "\(name) height")
        }

        // The defect, kept visible: a square of the card's width leaves a
        // landscape photograph short of the card's height.
        let square = CGSize(width: card.width, height: card.width)
        let before = filled(CGSize(width: 4032, height: 3024), into: square)
        XCTAssertGreaterThan(card.height / before.height, 1.3, "precondition: the square decode upscaled landscapes")
    }
}
