@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import XCTest

/// **How many of a stop's photographs the film actually shows, at real trip
/// scale** (2026-08-04).
///
/// The committed fixtures are small — Iceland 16 photos over 6 stops, New
/// Zealand 13 over 3 — and at that size every stop can afford its whole deck.
/// The defect this file exists for only appears above roughly ten stops, so it
/// was invisible to CI, to every desk stage, and to the golden-frame gates, and
/// was found only by measuring a real 170-photo dump by hand.
///
/// **The scale is generated, not dumped.** A fixture big enough to reproduce it
/// would be a real person's location history, which never enters this repository
/// (CLAUDE.md §0) — and a gitignored dump cannot run in CI by definition. So the
/// trip is built here from arithmetic: the same `ImportService` the app uses, fed
/// synthetic coordinates on a line, at a scale that matches a real multi-day
/// trip. Nothing about the defect depends on *where* the stops are, only on how
/// many there are and how many photographs each one carries.
final class RecapDeckBudgetTests: XCTestCase {

    /// Builds an imported trip of `stops` stops, each carrying `photosPerStop`
    /// photographs, through the real clusterer and repository.
    private func trip(
        stops: Int, photosPerStop: Int, config: TrackingConfig
    ) async throws -> RecapTrip {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)

        var photos: [ImportPhoto] = []
        for stop in 0..<stops {
            // Each stop sits its own gap apart in time and well outside
            // `stop_radius_m`, so the clusterer yields exactly `stops` clusters.
            let base = Double(stop) * (config.photoImport.stopSplitGapS + 3_600)
            let lat = 64.0 + Double(stop) * 0.2
            for photo in 0..<photosPerStop {
                photos.append(ImportPhoto(
                    assetId: "s\(stop)-p\(photo)", timestamp: base + Double(photo) * 60,
                    lat: lat, lon: -20.0
                ))
            }
        }

        let tripId = try await service.importTrip(title: "scale", photos: photos)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops.count, stops, "the clusterer must produce the scale under test")

        var photosByStop: [String: [PhotoRef]] = [:]
        for stop in detail.stops {
            let ordered = detail.photos.filter { $0.stopId == stop.id }.map(\.phAssetId)
            let selected = PhotoDeckSelector.evenlySpread(
                ordered, min: config.photoImport.deckMinPhotos, max: config.photoImport.deckMaxPhotos
            )
            if !selected.isEmpty { photosByStop[stop.id] = selected.map(PhotoRef.asset) }
        }
        let legs = RecapComposer.legs(
            from: detail.segments, epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        return try XCTUnwrap(RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: detail.stops, stats: nil,
            photosByStop: photosByStop,
            deck: RecapDeck(
                photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS,
                labelLeadS: config.export.deckLabelLeadS, photoMinHoldS: config.export.deckPhotoMinHoldS
            ),
            stopHoldS: config.export.stopHoldS
        ))
    }

    /// The largest deck each stop reaches, read off the timeline the renderer
    /// consumes. Keyed by the stop's first photo, which is unique per stop.
    private func photosShownPerStop(_ line: LinearTimeline, trip: RecapTrip) -> [Int] {
        var shown: [String: Int] = [:]
        var time = 0.0
        let step = 1.0 / 30
        while time <= line.durationS {
            for content in line.overlayContents(atTime: time) {
                guard case let .photoDeck(deck) = content, deck.opacity > 0.001,
                      case let .asset(key)? = deck.photos.first else { continue }
                shown[key] = max(shown[key] ?? 0, deck.photos.count)
            }
            time += step
        }
        return trip.stops.compactMap { stop -> Int? in
            guard case let .asset(key)? = stop.photos.first else { return nil }
            return shown[key] ?? 0
        }
    }

    private func timeline(_ trip: RecapTrip, config: TrackingConfig.Export) throws -> LinearTimeline {
        // An explicit extent rather than an installed region: CI has no tiles, and
        // a nil extent silently switches the film onto the retired flat duration
        // (LinearTimeline's documented pacing defect), which is not what is under
        // test here.
        let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
        return try XCTUnwrap(LinearTimeline(
            trip: trip, config: config,
            establishing: RecapBounds(
                minLat: bounds.minLat, minLon: bounds.minLon,
                maxLat: bounds.maxLat, maxLon: bounds.maxLon
            )
        ))
    }

    /// A small trip's decks, **re-baselined 2026-08-14 when duration began scaling
    /// with stop count** (Chiu). This asserted `>= 3` photographs on every stop of a
    /// four-stop trip, which held while every film was clamped to
    /// `total_duration_max_s` — a four-stop trip got the same 90 s as a sixty-stop
    /// one. It now earns 50 s, floored to `total_duration_min_s` (60 s), and the
    /// global scale plus `first_stop_dwell_scale` (0.55) puts the first stop under
    /// the deck floor at **[2, 6, 6, 6]**.
    ///
    /// **This is the third of the three resolutions the guard below already named**
    /// — "a longer cut, a lower photo floor, or duration that scales with stop
    /// count" — and Chiu chose it. The expectation changed because the product rule
    /// changed, not to make a red test green.
    ///
    /// **Why accept a shallower first deck sight-unseen** (Chiu 2026-08-14, recorded
    /// so it is not re-litigated): *no small-trip film has ever been rendered.*
    /// Margaret River and Finland are not gate trips and nobody has watched one.
    /// Deciding a film's photo depth blind from arithmetic is exactly what the
    /// render-before-you-rule step existed to prevent, so the depth question waits
    /// for a rendered small-trip cut rather than being settled by a threshold now.
    ///
    /// Separately iceboxed, not discarded: `first_stop_dwell_scale` is
    /// scale-invariant in intent but scale-dependent in effect, which is why the
    /// first stop is the one that falls through the floor here.
    func testASmallTripShowsWholeDecks() async throws {
        let config = AppConfig.loadOrDie()
        let recap = try await trip(stops: 4, photosPerStop: 8, config: config)
        let shown = photosShownPerStop(try timeline(recap, config: config.export), trip: recap)
        XCTAssertEqual(shown.count, 4)
        XCTAssertEqual(
            shown, [2, 6, 6, 6],
            "a four-stop trip is a 60 s film: the first stop shows 2 and the rest show whole decks"
        )
        XCTAssertTrue(
            shown.dropFirst().allSatisfy { $0 >= 3 },
            "only the first stop pays the dwell scale; the rest must still show real decks; got \(shown)"
        )
    }

    /// **The guard.** At real multi-day scale every stop is squeezed to a single
    /// photograph: the film's `total_duration_max_s` ceiling scales all dwells
    /// down, and `deck_photo_min_hold_s` then truncates each deck to what its
    /// window can afford at a second apiece.
    ///
    /// Currently expected to fail — the defect is real and unfixed (owner
    /// decision pending on whether the answer is a longer cut, a lower photo
    /// floor, or duration that scales with stop count). The expectation is here so
    /// the day it starts passing, this test says so instead of staying quietly
    /// green forever.
    func testARealScaleTripDoesNotCollapseToOnePhotoPerStop() async throws {
        let config = AppConfig.loadOrDie()
        // This guard documents the *unmitigated* collapse — the pacing a film gets
        // when nothing selects stops for it. `.highlight` and `.full` both exist to
        // fix it, so it can only be measured in one of them by measuring what the
        // policy is protecting against.
        try XCTSkipIf(
            config.export.recapMode == .highlight,
            "`.highlight` selects stops by budget; this guard measures the collapse it prevents."
        )
        let recap = try await trip(stops: 20, photosPerStop: 8, config: config)
        let shown = photosShownPerStop(try timeline(recap, config: config.export), trip: recap)
        XCTAssertEqual(shown.count, 20)

        XCTExpectFailure(
            "Known defect (2026-08-04): a 20-stop trip collapses to one photo per stop. "
            + "Remove this expectation when the duration/floor decision lands."
        )
        let collapsed = shown.filter { $0 <= 1 }.count
        XCTAssertLessThanOrEqual(
            collapsed, shown.count / 4,
            "\(collapsed) of \(shown.count) stops show a single photograph — decks per stop: \(shown)"
        )
    }

    /// TEMPORARY (2026-08-04): sweeps film durations against a **real** fixture so
    /// the duration-by-stop-count ratio can be judged on real data. Delete once the
    /// ratio is decided.
    ///
    ///     TEST_RUNNER_KAMOME_BUDGET_FIXTURE=iceland …
    func testReportRealFixtureBudgetSweep() async throws {
        let fixture = HarnessEnv.value("KAMOME_BUDGET_FIXTURE") ?? ""
        try XCTSkipUnless(!fixture.isEmpty, "Manual measurement — set KAMOME_BUDGET_FIXTURE.")
        let (recap, base) = try await RecapDemoFilmTests.importedRecap(named: fixture)
        let waypoints = recap.stops.filter(\.photos.isEmpty).count
        print("KAMOME_SWEEP \(fixture): \(recap.stops.count) stops (\(waypoints) waypoints, "
            + "\(recap.stops.count - waypoints) highlights)")

        let durations = (HarnessEnv.value("KAMOME_BUDGET_DURATIONS") ?? "30,60,90,180")
            .split(separator: ",").compactMap { Double($0) }
        for duration in durations {
            let config = base.withTotalDuration(min: duration, max: duration)
            let line = try timeline(recap, config: config)
            let shown = photosShownPerStop(line, trip: recap)
            let deck = shown.filter { $0 > 0 }
            let selected = recap.stops.reduce(0) { $0 + $1.photos.count }
            print(String(
                format: "  %5.0fs film · shown/stop min %d max %d mean %.1f · %d of %d selected photos · "
                    + "%d stops on 1 photo",
                line.durationS, deck.min() ?? 0, deck.max() ?? 0,
                deck.isEmpty ? 0 : Double(deck.reduce(0, +)) / Double(deck.count),
                shown.reduce(0, +), selected, deck.filter { $0 <= 1 }.count
            ))
        }
    }

    /// The measurement behind the guard, so a change in the numbers is visible in
    /// the log even while the expectation above is suppressing the failure.
    func testReportRealScaleDeckBudget() async throws {
        let config = AppConfig.loadOrDie()
        for stops in [4, 10, 20, 40] {
            let recap = try await trip(stops: stops, photosPerStop: 8, config: config)
            let line = try timeline(recap, config: config.export)
            let shown = photosShownPerStop(line, trip: recap)
            print(String(
                format: "KAMOME_DECK_BUDGET %2d stops · film %.0fs · shown/stop min %d max %d · %d of %d selected",
                stops, line.durationS, shown.min() ?? 0, shown.max() ?? 0,
                shown.reduce(0, +), recap.stops.reduce(0) { $0 + $1.photos.count }
            ))
        }
    }
}
