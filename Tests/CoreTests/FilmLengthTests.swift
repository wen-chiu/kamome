import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **The short film fits 90 s; the standard film is untouched** (Chiu
/// 2026-09-27: 精華版確定可以縮到一分半鐘，配合社群媒體的 Reels 限長).
///
/// Against the **shipped** values, because "fits a Reel" is only a promise
/// about what the app actually ships.
final class FilmLengthTests: XCTestCase {
    private func shipped() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    /// Eight stops at the expected photo mix price 88 s, and a ninth would be
    /// 97.5 s — so the short film's room is exactly the largest count under the
    /// ceiling, never one past it.
    func testShortHoldsTheMostStopsThatFitTheCeiling() throws {
        let config = try shipped()
        let room = StopPhotoAllocator.shortStopCount(config: config)
        XCTAssertEqual(room, 8, "at the shipped values")
        XCTAssertLessThanOrEqual(
            StopPhotoAllocator.earnedDurationS(presentedStops: room, config: config), config.totalDurationMaxS
        )
        XCTAssertGreaterThan(
            StopPhotoAllocator.earnedDurationS(presentedStops: room + 1, config: config), config.totalDurationMaxS
        )
    }

    /// Every stop marked — the case `.standard` grows past its earned count
    /// for (Chiu 2026-09-24). A short film keeps its room anyway.
    func testShortNeverGrowsPastItsRoomForMarks() throws {
        let config = try shipped()
        let signals = (0..<30).map { StopPhotoAllocator.Signal(photoCount: 10 + $0, favoriteCount: 1) }
        let short = StopPhotoAllocator.triage(signals, config: config, length: .short)
        let standard = StopPhotoAllocator.triage(signals, config: config, length: .standard)
        XCTAssertEqual(short.compactMap { $0 }.count, StopPhotoAllocator.shortStopCount(config: config))
        XCTAssertEqual(standard.compactMap { $0 }.count, 30, "precondition: standard keeps every marked stop")
    }

    /// A marked stop outranks a more-photographed unmarked one for the short
    /// film's room: the mark is the person saying so.
    func testShortFillsItsRoomWithMarkedStopsFirst() throws {
        let config = try shipped()
        var signals = (0..<20).map { StopPhotoAllocator.Signal(photoCount: 100 - $0) }
        signals[19] = StopPhotoAllocator.Signal(photoCount: 4, favoriteCount: 1)
        let short = StopPhotoAllocator.triage(signals, config: config, length: .short)
        XCTAssertNotNil(short[19], "the marked stop is kept despite the fewest photographs")
        XCTAssertNil(short[7], "and the lowest-ranked unmarked stop that would have fitted gives way")
        XCTAssertEqual(StopPhotoAllocator.priorityOrder(signals, config: config).first, 19)
    }

    /// Highlights lifted every deck to five: the fit gives back the extra
    /// photographs before it gives up a stop, and lands under the ceiling.
    func testTheFitTrimsLiftedDecksBeforeItDropsStops() throws {
        let config = try shipped()
        let lifted = (0..<8).map { StopPhotoAllocator.PresentedDeck(photos: config.tierTopPhotos, priority: $0) }
        let fitted = StopPhotoAllocator.fittedToCeiling(lifted, ceilingS: config.totalDurationMaxS, config: config)
        XCTAssertEqual(fitted.compactMap { $0 }.count, 8, "trimming alone was enough — no stop left")
        XCTAssertEqual(fitted.first, config.tierTopPhotos, "the highest priority keeps its lift")
        XCTAssertLessThanOrEqual(
            StopPhotoAllocator.earnedDurationS(photoCounts: fitted.compactMap { $0 }, config: config),
            config.totalDurationMaxS
        )
    }

    /// When trimming is not enough, the lowest priority leaves first.
    func testTheFitDropsTheLowestPriorityStopFirst() throws {
        let config = try shipped()
        let decks = (0..<12).map { StopPhotoAllocator.PresentedDeck(photos: config.tierStandardPhotos, priority: $0) }
        let fitted = StopPhotoAllocator.fittedToCeiling(decks, ceilingS: config.totalDurationMaxS, config: config)
        let kept = fitted.compactMap { $0 }.count
        XCTAssertLessThan(kept, 12)
        XCTAssertTrue(fitted.prefix(kept).allSatisfy { $0 != nil }, "the survivors are the top of the priority")
        XCTAssertTrue(fitted.dropFirst(kept).allSatisfy { $0 == nil })
        XCTAssertLessThanOrEqual(
            StopPhotoAllocator.earnedDurationS(photoCounts: fitted.compactMap { $0 }, config: config),
            config.totalDurationMaxS
        )
    }

    /// A film that already fits is returned as it came.
    func testTheFitLeavesAFilmThatFitsAlone() throws {
        let config = try shipped()
        let decks = (0..<5).map { StopPhotoAllocator.PresentedDeck(photos: config.tierTopPhotos, priority: $0) }
        let fitted = StopPhotoAllocator.fittedToCeiling(decks, ceilingS: config.totalDurationMaxS, config: config)
        XCTAssertEqual(fitted, decks.map { Optional($0.photos) })
    }

    /// Each length has its own ceiling: 90 s for a Reel, 300 s for the whole
    /// trip (Chiu 2026-09-27: 標準預設不要超過三百秒).
    func testEachLengthHasItsOwnCeiling() throws {
        let config = try shipped()
        XCTAssertEqual(config.durationCeilingS(for: .short), 90)
        XCTAssertEqual(config.durationCeilingS(for: .standard), 300)
    }

    /// **Every copy keeps the standard ceiling.** The initialiser defaults it to
    /// no ceiling for hand-built configs, so a copy that forgot to pass it would
    /// compile and silently lift the cap — on the harness paths, not in the app.
    func testEveryCopyKeepsTheStandardCeiling() throws {
        let base = try shipped()
        let copies: [TrackingConfig.Export] = [
            base.withFollowHeadingUp(!base.followHeadingUp),
            base.withAllocationZeroShare(base.allocationZeroShare),
            base.withRecapMode(base.recapMode),
            base.withTotalDuration(min: base.totalDurationMinS, max: base.totalDurationMaxS),
            base.withCrossingBeatS(base.crossingBeatS),
            base.withKeyframeIntervalFrames(base.keyframeIntervalFrames),
            base.withSnapshotStations(
                maxMagnification: base.snapshotStationMaxMagnification, padding: base.snapshotStationPadding
            )
        ]
        for copy in copies {
            XCTAssertEqual(copy.standardDurationMaxS, base.standardDurationMaxS)
        }
    }
}
