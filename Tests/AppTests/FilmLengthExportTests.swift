@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import XCTest

/// **The short film, end to end** (Chiu 2026-09-27): through the importer, the
/// composer's own selection and deck pick, and the timeline the renderer
/// consumes — the length a viewer gets, not the length a formula promised.
///
/// Synthetic scale, for the reason `RecapDeckBudgetTests` gives: the case under
/// test needs many stops, and a real dump never enters this repository (§0).
@MainActor
final class FilmLengthExportTests: XCTestCase {
    private struct Imported {
        let repository: TripRepository
        let detail: TripRepository.TripDetail
    }

    /// `stops` stops of `photosPerStop` photographs, the last `markedPerStop`
    /// of each a Photos favourite — so every deck is lifted by highlights.
    private func imported(
        stops: Int, photosPerStop: Int, markedPerStop: Int, config: TrackingConfig
    ) async throws -> Imported {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)
        var photos: [ImportPhoto] = []
        for stop in 0..<stops {
            let base = Double(stop) * (config.photoImport.stopSplitGapS + 3_600)
            // More photographs at later stops, so the ranking is not a tie.
            for photo in 0..<(photosPerStop + stop) {
                photos.append(ImportPhoto(
                    assetId: "s\(stop)-p\(photo)", timestamp: base + Double(photo) * 60,
                    lat: 64.0 + Double(stop) * 0.2, lon: -20.0,
                    isFavorite: photo < markedPerStop
                ))
            }
        }
        let tripId = try await service.importTrip(title: "length", photos: photos)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops.count, stops, "the clusterer must produce the scale under test")
        return Imported(repository: repository, detail: detail)
    }

    private func film(_ detail: TripRepository.TripDetail, length: FilmLength, config: TrackingConfig) throws -> RecapTrip {
        let inputs = RecapComposer.photoInputs(detail: detail)
        let legs = RecapComposer.legs(
            from: detail.segments, epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        return try XCTUnwrap(RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: detail.stops, stats: nil,
            photosByStop: inputs.byStop,
            deck: RecapDeck(
                photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS,
                labelLeadS: config.export.deckLabelLeadS, photoMinHoldS: config.export.deckPhotoMinHoldS
            ),
            stopHoldS: config.export.stopHoldS,
            rawPhotoCounts: inputs.rawCounts, favoriteCounts: inputs.starredCounts,
            highlightedAssets: inputs.highlighted,
            pickedAssets: inputs.picked, pickedCounts: inputs.pickedCounts,
            highlightMaxPhotos: config.photoImport.deckHighlightMaxPhotos,
            weighting: config.export, length: length
        ))
    }

    private func timeline(_ trip: RecapTrip, config: TrackingConfig.Export) throws -> LinearTimeline {
        // An explicit extent, as `RecapDeckBudgetTests` does: CI has no tiles.
        let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
        return try XCTUnwrap(LinearTimeline(
            trip: trip, config: config,
            establishing: RecapBounds(
                minLat: bounds.minLat, minLon: bounds.minLon, maxLat: bounds.maxLat, maxLon: bounds.maxLon
            )
        ))
    }

    /// Thirty stops, every one marked and every deck lifted to five — the trip
    /// whose standard film ran 382 s before it had a ceiling. Each length is at
    /// most its own ceiling on the timeline itself (90 s, 300 s).
    func testEachLengthFitsItsCeilingOnTheTimeline() async throws {
        let config = AppConfig.loadOrDie()
        try XCTSkipIf(config.export.recapMode != .highlight, "measures the shipped Variant B path")
        let trip = try await imported(stops: 30, photosPerStop: 12, markedPerStop: 8, config: config).detail
        let short = try timeline(film(trip, length: .short, config: config), config: config.export)
        let standard = try timeline(film(trip, length: .standard, config: config), config: config.export)
        let frame = 1.0 / Double(config.export.fps)
        print("KAMOME_FILM_LENGTH short \(short.durationS)s · standard \(standard.durationS)s")
        XCTAssertLessThanOrEqual(short.durationS, config.export.durationCeilingS(for: .short) + frame)
        XCTAssertLessThanOrEqual(standard.durationS, config.export.durationCeilingS(for: .standard) + frame)
        XCTAssertGreaterThan(standard.durationS, config.export.durationCeilingS(for: .short),
                             "precondition: this trip's standard film is longer than a short one")
    }

    /// **The length on the sheet is the timeline's length** (reopening ADR
    /// 2026-09-26 (c) item 7): for a local trip the estimate from the decks
    /// alone equals what the timeline builds, to the frame, in both lengths.
    func testTheEstimateIsTheTimelinesLength() async throws {
        let config = AppConfig.loadOrDie()
        let trip = try await imported(stops: 14, photosPerStop: 6, markedPerStop: 1, config: config).detail
        for length in FilmLength.allCases {
            let recap = try film(trip, length: length, config: config)
            let line = try timeline(recap, config: config.export)
            let estimate = RecapComposer.estimatedFilmS(photoCounts: recap.stops.map(\.photos.count), config: config)
            XCTAssertEqual(estimate, line.durationS, accuracy: 1.0 / Double(config.export.fps), "\(length)")
        }
    }

    /// **A stop put in joins the short film and moves nothing else**
    /// (Chiu 2026-09-25) — even though it carries the film past its ceiling.
    /// The first version fitted the finished plan and dropped one of the app's
    /// stops to make room; the ceiling binds the app's choice only.
    func testAStopPutIntoAShortFilmMovesNoOtherStop() async throws {
        let config = AppConfig.loadOrDie()
        let trip = try await imported(stops: 30, photosPerStop: 12, markedPerStop: 0, config: config)
        let before = RecapComposer.filmPlan(detail: trip.detail, config: config, length: .short)
        let outside = try XCTUnwrap(trip.detail.stops.first { before.decks[$0.id] == nil })
        try trip.repository.setStopFilmChoice(stopId: outside.id, choice: .included)
        let detail = try XCTUnwrap(try trip.repository.detail(tripId: trip.detail.trip.id))
        let after = RecapComposer.filmPlan(detail: detail, config: config, length: .short)
        XCTAssertNotNil(after.decks[outside.id])
        var expected = before.decks
        expected[outside.id] = after.decks[outside.id]
        XCTAssertEqual(after.decks, expected, "every other stop keeps its place and its deck")
    }

    /// Short is where the sheet opens until the person picks otherwise
    /// (Chiu 2026-09-27: 預設等級：精華), and the pick is remembered.
    func testTheSheetOpensOnShortAndRemembersAChoice() throws {
        let suite = "FilmLengthExportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FilmLengthChoice.current(defaults: defaults), .short)
        FilmLengthChoice.remember(.standard, defaults: defaults)
        XCTAssertEqual(FilmLengthChoice.current(defaults: defaults), .standard)
        defaults.set("cinematic", forKey: "kamome.filmLength")
        XCTAssertEqual(FilmLengthChoice.current(defaults: defaults), .short, "an unknown value reads as the default")
    }

    /// The kept export logs roll: the newest `keeping` exports survive, whole.
    func testTheExportLogHistoryKeepsTheNewestExportsWhole() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var text = ""
        for index in 0..<5 {
            let line = DiagnosticsLog.Line(
                date: start, category: "recap", level: "notice", message: "render cost: export \(index)"
            )
            text = ExportLogHistory.appending(
                block: ExportLogHistory.block(start: start, lines: [line]), to: text, keeping: 3
            )
        }
        XCTAssertEqual(text.components(separatedBy: ExportLogHistory.blockMark).count - 1, 3)
        XCTAssertFalse(text.contains("export 1\n"))
        XCTAssertTrue(text.contains("export 2\n"))
        XCTAssertTrue(text.hasSuffix("render cost: export 4\n"))
        XCTAssertTrue(text.hasPrefix(ExportLogHistory.blockMark))
    }

    /// **Too long is said, not fixed** (Chiu 2026-09-27: 如果還是太長，要給提醒).
    /// Every stop put in by hand carries the short film past 90 s; the sheet's
    /// model says so, and keeps every one of them.
    func testStopsPutInPastTheCeilingAreKeptAndFlagged() async throws {
        let config = AppConfig.loadOrDie()
        let trip = try await imported(stops: 30, photosPerStop: 12, markedPerStop: 0, config: config)
        let choices = FilmPhotoChoices(
            tripId: trip.detail.trip.id, config: config, repository: trip.repository, length: .short
        )
        XCTAssertFalse(choices.isOverCeiling(photosEnabled: true), "the app's own choice fits")
        for stop in choices.otherStops { choices.putIn(stopId: stop.id) }
        XCTAssertEqual(choices.filmStops.count, 30)
        XCTAssertTrue(choices.isOverCeiling(photosEnabled: true))
    }
}
