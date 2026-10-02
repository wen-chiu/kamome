@testable import Kamome
import KamomeConfig
import XCTest

/// **"About N minutes left", from the export's own pace** (Chiu 2026-09-30,
/// issue #151). The arithmetic is pure — elapsed seconds are handed in — so
/// each of the decision's three rules is a test here: a warm-up before any
/// number, a rate counted in stations rather than frames, and a number that
/// does not flicker upwards.
final class RecapExportTimeLeftTests: XCTestCase {
    private let pipeline = TrackingConfig.ExportPipeline(
        prefetchDepth: 8, compositeConcurrency: 4, snapshotTimeoutS: 60, mapCacheMb: 256,
        coalesceTileRequests: true, terrainMaxAgeS: 0, tileMemoryMb: 64, keptExportLogs: 20,
        estimateWarmupS: 60, estimateRiseToleranceMin: 1
    )

    /// 100 stations of 10 frames each over 1,000 frames: a film with no stop
    /// beats, where stations and frames advance together.
    private func even() -> RecapExportTimeLeft {
        RecapExportTimeLeft(stationEnds: (1...100).map { $0 * 10 }, frameCount: 1000, pipeline: pipeline)
    }

    // MARK: - Warm-up

    func testNothingIsSaidInsideTheWarmUp() {
        var estimate = even()
        XCTAssertNil(estimate.update(fraction: 0.2, elapsedS: 30), "30 s is inside the 60 s warm-up")
        XCTAssertNil(estimate.update(fraction: 0.3, elapsedS: 59.9))
        XCTAssertNotNil(estimate.update(fraction: 0.3, elapsedS: 60), "the warm-up ends at the threshold")
    }

    func testTheWarmUpIsReadFromTheConfig() throws {
        let shippedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        let shipped = try TrackingConfigLoader.load(contentsOf: shippedURL).export.pipeline
        let estimate = RecapExportTimeLeft(stationEnds: [10], frameCount: 10, pipeline: shipped)
        XCTAssertEqual(estimate.warmupS, shipped.estimateWarmupS)
        XCTAssertEqual(estimate.riseToleranceMin, shipped.estimateRiseToleranceMin)
    }

    func testNothingIsSaidBeforeTheFirstStationIsDone() {
        var estimate = even()
        // 9 frames delivered: the first station (frames 0..<10) is not done.
        XCTAssertNil(estimate.update(fraction: 0.009, elapsedS: 120))
    }

    // MARK: - The rate is stations, not frames

    func testTheRemainderIsExtrapolatedFromTheExportsOwnPace() throws {
        let estimate = even()
        // 25 of 100 stations in 100 s: 0.25 stations/s, 75 left → 300 s.
        XCTAssertEqual(try XCTUnwrap(estimate.remainingS(fraction: 0.25, elapsedS: 100)), 300, accuracy: 1e-9)
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: 300), .minutes(5))
    }

    /// **Why stations.** One stop beat holds a single station for 500 of the
    /// film's 1,000 frames. Half the frames are delivered once that station is
    /// done, but only 11 of 61 stations are — so the export is nowhere near half
    /// way, and a frame-based extrapolation would say ~2 minutes where the
    /// honest answer is ~9.
    func testAStopBeatHeldOnOneStationDoesNotReadAsHalfTheWork() throws {
        let travelBefore = (1...10).map { $0 * 10 }          // frames 0..<100, 10 stations
        let stopBeat = [600]                                   // frames 100..<600, 1 station
        let travelAfter = (1...49).map { 600 + $0 * 8 }        // frames 600..<992, 49 stations
        let ends = travelBefore + stopBeat + travelAfter + [1000]
        let estimate = RecapExportTimeLeft(stationEnds: ends, frameCount: 1000, pipeline: pipeline)
        XCTAssertEqual(estimate.stationsDone(fraction: 0.6), 11)
        // 11 stations in 120 s; 50 remain → 545 s.
        let remaining = try XCTUnwrap(estimate.remainingS(fraction: 0.6, elapsedS: 120))
        XCTAssertEqual(remaining, 50 / (11 / 120.0), accuracy: 1e-9)
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: remaining), .minutes(9))
        let frameBasedS = 120 / 0.6 * 0.4
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: frameBasedS), .minutes(1), "what frames would have said")
    }

    func testStationsDoneCountsOnlyWhollyDeliveredStations() {
        let estimate = even()
        XCTAssertEqual(estimate.stationsDone(fraction: 0), 0)
        XCTAssertEqual(estimate.stationsDone(fraction: 0.019), 1, "19 frames: station 2 is not done")
        XCTAssertEqual(estimate.stationsDone(fraction: 0.02), 2)
        XCTAssertEqual(estimate.stationsDone(fraction: 1), 100)
    }

    // MARK: - Wording

    func testSecondsAreWordedAsTheNearestMinuteOrUnderOne() {
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: 0), .underAMinute)
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: 59.9), .underAMinute)
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: 60), .minutes(1))
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: 89), .minutes(1))
        XCTAssertEqual(RecapExportTimeLeft.reading(seconds: 91), .minutes(2))
    }

    func testTheLastFrameReadsAsUnderAMinute() {
        var estimate = even()
        XCTAssertEqual(estimate.update(fraction: 1, elapsedS: 400), .underAMinute)
    }

    // MARK: - Monotone-ish

    func testAFallingEstimateIsShownAtOnce() {
        var estimate = even()
        XCTAssertEqual(estimate.update(fraction: 0.25, elapsedS: 100), .minutes(5))
        XCTAssertEqual(estimate.update(fraction: 0.50, elapsedS: 200), .minutes(3))
    }

    func testARiseWithinTheToleranceIsHeldBack() {
        var estimate = even()
        XCTAssertEqual(estimate.update(fraction: 0.25, elapsedS: 100), .minutes(5))
        // One slow station: 26 in 118 s → 74 left at 0.2203/s ≈ 336 s ≈ 6 min.
        XCTAssertEqual(estimate.update(fraction: 0.26, elapsedS: 118), .minutes(5), "5 → 6 is within 1 minute")
    }

    func testARealSlowdownGetsThrough() {
        var estimate = even()
        XCTAssertEqual(estimate.update(fraction: 0.25, elapsedS: 100), .minutes(5))
        // Throttled: 26 stations in 160 s → 74 left at 0.1625/s ≈ 455 s ≈ 8 min.
        XCTAssertEqual(estimate.update(fraction: 0.26, elapsedS: 160), .minutes(8))
    }

    /// A steady export never shows a number above one it has already shown —
    /// the property the user sees, walked end to end.
    func testASteadyExportCountsDownWithoutEverRising() {
        var estimate = even()
        var shown: [Int] = []
        for second in stride(from: 0.0, through: 400, by: 0.5) {
            // 0.25 stations/s, with a wobble of ±0.2 stations to mimic stations of
            // uneven cost; the average pace stays steady.
            let wobble = sin(second) * 0.2
            let fraction = min(1, (second * 0.25 + wobble) * 10 / 1000)
            if let reading = estimate.update(fraction: max(0, fraction), elapsedS: second) {
                shown.append(reading.wholeMinutes)
            }
        }
        XCTAssertFalse(shown.isEmpty)
        XCTAssertEqual(shown, shown.sorted(by: >), "the number only ever falls")
        XCTAssertEqual(shown.last, 0)
    }

    // MARK: - Wiring

    /// The job hands the plan over as drawing starts and the coordinator feeds
    /// it every progress report — and inside the warm-up the running export
    /// says nothing, which is what keeps the first minute to a percentage.
    @MainActor
    func testTheRunningExportCarriesTheEstimateAndIsSilentInsideTheWarmUp() async {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(
            request: RecapExportRequest(tripId: "trip-a", photosEnabled: true, format: .mp4, appearance: .dark),
            job: job
        )
        for _ in 0..<10_000 where !job.hasStarted { await Task.yield() }
        XCTAssertTrue(job.hasStarted)
        XCTAssertNil(coordinator.running(tripId: "trip-a")?.timeLeft, "no plan before drawing starts")

        job.report(stage: .drawing)
        job.report(timeLeft: even())
        job.report(progress: 0.5)
        let running = coordinator.running(tripId: "trip-a")
        XCTAssertEqual(running?.timeLeft?.stationEnds.count, 100)
        XCTAssertNotNil(running?.drawingStarted)
        XCTAssertEqual(running?.fraction, 0.5)
        XCTAssertNil(running?.timeLeft?.reading, "half done in well under a minute is still the warm-up")

        job.complete(.cancelled)
        for _ in 0..<10_000 where coordinator.running(tripId: "trip-a") != nil { await Task.yield() }
    }
}
