@testable import Kamome
import KamomeImportKit
import XCTest

/// **A hidden journey is found by its photographs when its key moves** (#170).
/// A key is the journey's first day; a threshold change or a photograph added
/// before it moves that day. Keyed alone, the hidden journey came back and a
/// journey that took the old key was hidden in its place.
extension JourneyDiscoveryModelTests {
    /// A photograph two hours before the journey's first, away from home and
    /// after the evening's home photograph, falls on the UTC day before: the
    /// first day moves and so does the key, as a threshold change would.
    private func whitehorseStartsADayEarlier(_ harness: Harness) {
        harness.library.photos.append(
            ImportPhoto(assetId: "yt-early", timestamp: 30 * week - 2 * 3_600, lat: 60.72, lon: -135.05)
        )
    }

    func testAHiddenJourneyStaysHiddenWhenItsKeyMoves() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let whitehorse = try XCTUnwrap(harness.model.journeys.first)
        harness.model.hide(whitehorse)

        whitehorseStartsADayEarlier(harness)
        await harness.model.refresh()

        let hidden = try XCTUnwrap(harness.model.hiddenJourneys.first)
        XCTAssertNotEqual(hidden.id, whitehorse.id, "the key did move")
        XCTAssertEqual(harness.model.hiddenJourneys.count, 1)
        XCTAssertFalse(harness.model.journeys.contains { $0.id == hidden.id }, "still hidden under its new key")
        XCTAssertEqual(harness.model.journeys.count, 1, "and nothing else was hidden")

        harness.model.unhide(hidden)
        await harness.model.refresh()
        XCTAssertTrue(harness.model.hiddenJourneys.isEmpty, "shown again for good, under the new key")
        XCTAssertEqual(harness.model.journeys.count, 2)
    }

    /// A journey that now starts on a hidden journey's old day is not hidden
    /// for it: it holds none of the hidden journey's photographs.
    func testAJourneyThatTakesAHiddenKeyIsNotHidden() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let whitehorse = try XCTUnwrap(harness.model.journeys.first)
        harness.model.hide(whitehorse)

        // Whitehorse's photographs leave the library; a new journey elsewhere
        // begins on the same day.
        harness.library.photos.removeAll { $0.assetId.hasPrefix("yt-") }
        harness.library.photos += (0..<9).map {
            ImportPhoto(assetId: "nz-\($0)", timestamp: 30 * week + Double($0) * 1_800, lat: -45.03, lon: 168.66)
        }
        await harness.model.refresh()

        let newcomer = try XCTUnwrap(harness.model.journeys.first { $0.id == whitehorse.id }, "same key")
        XCTAssertFalse(newcomer.isImported)
        XCTAssertTrue(harness.model.hiddenJourneys.isEmpty, "the hidden journey is gone, so nothing shows as hidden")
    }

    /// A record made before #170 has only its key, and is matched by it as before.
    func testAHiddenKeyWithoutPhotographsIsStillHonoured() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let whitehorse = try XCTUnwrap(harness.model.journeys.first)
        DismissedJourneys(defaults: harness.defaults).dismiss(whitehorse.id)

        await harness.model.refresh()
        XCTAssertEqual(harness.model.hiddenJourneys.map(\.id), [whitehorse.id])
        XCTAssertFalse(harness.model.journeys.contains { $0.id == whitehorse.id })
    }
}
