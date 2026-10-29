import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **A failed map snapshot is asked again, from the same source, a bounded
/// number of times** (#330, Chiu 2026-10-29).
///
/// One snapshot that timed out used to fail the whole export. The retry may
/// not become a fallback, may not outlast its bound, and may not hold up a
/// Cancel: each of those is a test here, first on `SnapshotRetry` alone, then
/// through the render loop that uses it.
final class SnapshotRetryTests: RecapRenderTestCase {
    private struct Failure: Error, Equatable {
        let attempt: Int
    }

    /// Counts calls from inside async closures without a data race.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0
        var value: Int { lock.withLock { stored } }
        @discardableResult
        func next() -> Int { lock.withLock { stored += 1; return stored } }
    }

    // MARK: - SnapshotRetry alone

    func testASnapshotThatSucceedsIsAskedOnce() async throws {
        let attempts = Counter()
        let value = try await SnapshotRetry.run(
            delaysS: [0, 0], keepTrying: { true }, onRetry: { XCTFail("nothing failed") }, attempt: { attempts.next() }
        )
        XCTAssertEqual(value, 1)
        XCTAssertEqual(attempts.value, 1)
    }

    func testAFailureThatClearsIsAskedAgainAfterEachWait() async throws {
        let attempts = Counter()
        let retries = Counter()
        let value = try await SnapshotRetry.run(
            delaysS: [0, 0], keepTrying: { true }, onRetry: { retries.next() },
            attempt: { () async throws -> Int in
                let attempt = attempts.next()
                if attempt < 3 { throw Failure(attempt: attempt) }
                return attempt
            }
        )
        XCTAssertEqual(value, 3, "the third attempt is the one that succeeded")
        XCTAssertEqual(retries.value, 2)
    }

    func testEveryAttemptFailingThrowsTheLastErrorAfterOneAttemptPerWaitPlusOne() async {
        let attempts = Counter()
        do {
            _ = try await SnapshotRetry.run(delaysS: [0, 0], keepTrying: { true }, onRetry: {}, attempt: {
                () async throws -> Int in throw Failure(attempt: attempts.next())
            })
            XCTFail("a snapshot that never succeeds must still fail the export")
        } catch {
            XCTAssertEqual(error as? Failure, Failure(attempt: 3))
        }
        XCTAssertEqual(attempts.value, 3, "bounded: one attempt, then one per wait")
    }

    func testNoWaitsMeansNoRetry() async {
        let attempts = Counter()
        do {
            _ = try await SnapshotRetry.run(delaysS: [], keepTrying: { true }, onRetry: {}, attempt: {
                () async throws -> Int in throw Failure(attempt: attempts.next())
            })
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error as? Failure, Failure(attempt: 1))
        }
        XCTAssertEqual(attempts.value, 1)
    }

    func testACancellationIsNeverRetried() async {
        let attempts = Counter()
        do {
            _ = try await SnapshotRetry.run(delaysS: [0, 0], keepTrying: { true }, onRetry: {}, attempt: {
                () async throws -> Int in
                attempts.next()
                throw CancellationError()
            })
            XCTFail("expected the cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(attempts.value, 1, "a stopped export is not a failed snapshot")
    }

    func testCancelEndsTheRetriesBeforeTheWait() async {
        let attempts = Counter()
        let started = ContinuousClock.now
        do {
            _ = try await SnapshotRetry.run(delaysS: [30, 30], keepTrying: { false }, onRetry: {}, attempt: {
                () async throws -> Int in throw Failure(attempt: attempts.next())
            })
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error as? Failure, Failure(attempt: 1), "the attempt's own error, not a new one")
        }
        XCTAssertEqual(attempts.value, 1)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "Cancel waited out a retry")
    }

    func testCancelDuringTheWaitEndsTheRetries() async {
        let attempts = Counter()
        let checks = Counter()
        do {
            // Yes before the wait, no after it: the person pressed Cancel while
            // the export was waiting to ask again.
            _ = try await SnapshotRetry.run(
                delaysS: [0, 0], keepTrying: { checks.next() == 1 }, onRetry: {},
                attempt: { () async throws -> Int in throw Failure(attempt: attempts.next()) }
            )
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error as? Failure, Failure(attempt: 1))
        }
        XCTAssertEqual(attempts.value, 1)
    }

    // MARK: - Through the render loop

    /// Fails its first `failures` snapshots the way MapLibre does when tiles
    /// cannot be fetched (`MLNErrorDomain` 6), then draws as normal.
    private final class FlakyProvider: MapRenderer {
        private let inner = FlatSnapshotProvider()
        private let failures: Int
        let calls = Counter()

        init(failures: Int) { self.failures = failures }

        var capabilities: MapRendererCapabilities { inner.capabilities }

        func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
            guard calls.next() > failures else { throw NSError(domain: "MLNErrorDomain", code: 6) }
            return try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
        }
    }

    private func loop(provider: MapRenderer, retryDelaysS: [Double]) throws -> (RecapRenderLoop, frames: Int) {
        let base = TrackingConfig.ExportPipeline.handBuilt
        let pipeline = TrackingConfig.ExportPipeline(
            prefetchDepth: base.prefetchDepth, compositeConcurrency: base.compositeConcurrency,
            snapshotTimeoutS: base.snapshotTimeoutS, snapshotRetryDelaysS: retryDelaysS,
            mapCacheMb: base.mapCacheMb, coalesceTileRequests: base.coalesceTileRequests,
            terrainMaxAgeS: base.terrainMaxAgeS, tileMemoryMb: base.tileMemoryMb,
            keptExportLogs: base.keptExportLogs, estimateWarmupS: base.estimateWarmupS,
            estimateRiseToleranceMin: base.estimateRiseToleranceMin
        )
        let config = exportConfig(targetDurationS: 2, fps: 5, pipeline: pipeline)
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let loop = RecapRenderLoop(
            timeline: timeline, compositor: makeCompositor(timeline), provider: provider, config: config
        )
        return (loop, timeline.frameCount)
    }

    func testAFilmWhoseFirstSnapshotFailsIsStillDeliveredWhole() async throws {
        let provider = FlakyProvider(failures: 1)
        let (loop, frames) = try loop(provider: provider, retryDelaysS: [0.01, 0.01])
        var delivered: [Int] = []
        let stats = try await loop.renderFrames { frame, _ in
            delivered.append(frame)
            return true
        }
        XCTAssertEqual(delivered, Array(0..<frames), "every frame, in film order")
        XCTAssertEqual(stats.retries, 1)
        XCTAssertEqual(stats.fetches, provider.calls.value, "the retry is a fetch like any other")
    }

    func testAFilmWhoseMapNeverAnswersStillFails() async throws {
        let provider = FlakyProvider(failures: .max)
        let (loop, _) = try loop(provider: provider, retryDelaysS: [0.01, 0.01])
        do {
            try await loop.renderFrames { _, _ in true }
            XCTFail("a map that never draws must fail the export, never ship a film without it")
        } catch {
            let bridged = error as NSError
            XCTAssertEqual(bridged.domain, "MLNErrorDomain")
            XCTAssertEqual(bridged.code, 6)
        }
        XCTAssertGreaterThanOrEqual(provider.calls.value, 3, "the first station was asked once and twice again")
    }

    func testCancelIsNotHeldByARetry() async throws {
        let provider = FlakyProvider(failures: .max)
        let (loop, _) = try loop(provider: provider, retryDelaysS: [30, 30])
        let started = ContinuousClock.now
        do {
            let cancelled: () -> Bool = { false }
            try await loop.renderFrames(keepTrying: cancelled) { _, _ in true }
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, "MLNErrorDomain")
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(10), "Cancel waited out a 30 s retry")
    }
}
