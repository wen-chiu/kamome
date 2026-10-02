@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeTripComposer
import XCTest

/// **Trip Detail's read is off the main thread** (#128). `repository.detail`
/// carries every trackpoint; a two-week recording is ~200 000 of them
/// (`Docs/handoff-long-recording.md`), and the read ran inside `reload()` on
/// the main thread, once per appearance, rename, export outcome and geocoded
/// stop.
@MainActor
final class TripDetailReloadTests: XCTestCase {
    /// `winding` bends the track, so thinning has corners to keep rather than
    /// collapsing a straight line to its two ends.
    private func longTrip(points: Int, winding: Bool = false) throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let start = 1_787_382_000.0
        let track = (0 ..< points).map {
            TripRepository.NewTrackpoint(
                ts: start + Double($0), lat: 35.0 + Double($0) * 1e-5,
                lon: 139.0 + (winding ? 0.01 * sin(Double($0) / 2_000) : 0)
            )
        }
        let end = start + Double(points)
        let tripId = try repository.saveCompletedTrip(
            title: "long", startedAt: start, endedAt: end,
            segments: [TripRepository.NewSegment(mode: "drive", startedAt: start, endedAt: end, points: track)],
            stops: []
        )
        return (repository, tripId)
    }

    /// Returning before the rows are in is the property: had `reload()` read
    /// inline, `detail` would already be set when it returned.
    func testReloadReturnsBeforeTheReadFinishes() async throws {
        let (repository, tripId) = try longTrip(points: 200_000)
        let model = TripDetailModel(tripId: tripId, config: AppConfig.loadOrDie(), repository: repository)

        let started = CFAbsoluteTimeGetCurrent()
        model.reload()
        let onMain = CFAbsoluteTimeGetCurrent() - started
        XCTAssertNil(model.detail, "the read ran on the main thread")

        await model.refresh()
        let total = CFAbsoluteTimeGetCurrent() - started
        XCTAssertEqual(model.detail?.segments.first?.points.count, 200_000)
        // Measured, not asserted: a wall-clock bound would flake on CI runners.
        print("TRIPDETAIL_RELOAD 200k: main \(Int(onMain * 1000)) ms, read \(Int(total * 1000)) ms")
    }

    /// The first reload is superseded; the second's rows are what stay.
    func testALaterReadIsNeverOverwrittenByAnEarlierOne() async throws {
        let (repository, tripId) = try longTrip(points: 50_000)
        let model = TripDetailModel(tripId: tripId, config: AppConfig.loadOrDie(), repository: repository)
        model.reload()
        try repository.setTripTitle(tripId: tripId, title: "renamed")
        await model.refresh()
        try await Task.sleep(nanoseconds: 300_000_000) // let the superseded read land
        XCTAssertEqual(model.detail?.trip.title, "renamed")
    }

    /// **Renaming a trip nobody named starts from an empty field** (#177): it
    /// opened on the stored start date, which no screen shows, and typing
    /// added to it. The placeholder is the name this screen shows instead.
    func testRenamingAnUnnamedTripStartsEmptyAndANamedOneFromItsName() async throws {
        let (repository, tripId) = try longTrip(points: 10)
        let model = TripDetailModel(tripId: tripId, config: AppConfig.loadOrDie(), repository: repository)
        await model.refresh()
        XCTAssertEqual(model.renameDraft, "long")
        XCTAssertNil(model.renamePrompt)

        try repository.setTripTitle(tripId: tripId, title: TripTitle.unnamed)
        await model.refresh()
        XCTAssertEqual(model.renameDraft, "")
        XCTAssertEqual(model.renamePrompt, model.storyTitle)
        XCTAssertFalse(model.storyTitle.isEmpty, "an unnamed trip is never shown as a blank")

        let legacy = TripTitle.fallback(for: try XCTUnwrap(model.detail?.trip.startedAt))
        try repository.setTripTitle(tripId: tripId, title: legacy)
        await model.refresh()
        XCTAssertEqual(model.renameDraft, "", "a title that is the old date string is not a name to edit")
    }

    /// **The map's lines are thinned with the read, not in the view body**
    /// (#139). The map bodies called Douglas-Peucker on every segment on every
    /// render, on the main thread; now `refresh()` thins once, off it, and a
    /// render only looks the result up. The lines themselves must not change.
    func testDisplayPolylinesAreThinnedWithTheReadAndUnchanged() async throws {
        let (repository, tripId) = try longTrip(points: 200_000, winding: true)
        let config = AppConfig.loadOrDie()
        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        await model.refresh()

        let item = try XCTUnwrap(model.detail?.segments.first)
        let started = CFAbsoluteTimeGetCurrent()
        let expected = Simplifier.douglasPeucker(
            item.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) },
            epsilonM: config.simplify.epsilonM
        )
        let perRenderBefore = CFAbsoluteTimeGetCurrent() - started

        let lookedUp = CFAbsoluteTimeGetCurrent()
        let line = model.displayPolyline(for: item.segment)
        let perRenderNow = CFAbsoluteTimeGetCurrent() - lookedUp

        XCTAssertGreaterThan(line.count, 20, "the fixture no longer winds, so this compares two endpoints")
        XCTAssertEqual(line, expected, "thinning moved, and the line changed with it")
        // Measured, not asserted: a wall-clock bound would flake on CI runners.
        print("TRIPDETAIL_POLYLINE 200k: per render before \(Int(perRenderBefore * 1000)) ms, "
            + "now \(Int(perRenderNow * 1_000_000)) µs; \(line.count) points drawn")
    }
}
