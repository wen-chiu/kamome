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

    /// A small trip is fine, and this is exactly why the committed fixtures never
    /// caught the defect — it pins the boundary so the guard below cannot be
    /// dismissed as a bad measurement.
    func testASmallTripShowsWholeDecks() async throws {
        let config = AppConfig.loadOrDie()
        let recap = try await trip(stops: 4, photosPerStop: 8, config: config)
        let shown = photosShownPerStop(try timeline(recap, config: config.export), trip: recap)
        XCTAssertEqual(shown.count, 4)
        XCTAssertTrue(
            shown.allSatisfy { $0 >= 3 },
            "a four-stop trip has room for real decks; got \(shown)"
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
