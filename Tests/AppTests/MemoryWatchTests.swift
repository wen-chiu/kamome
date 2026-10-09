@testable import Kamome
import XCTest

/// The reading behind the `render memory` log line (#161): the largest footprint
/// and the least headroom an export saw, so a phone run without Xcode can say
/// how close it came to jetsam. A diagnostic that reads zero because its reader
/// never worked is worse than none, so the real reader is exercised too.
final class MemoryWatchTests: XCTestCase {
    private static let mb: UInt64 = 1_048_576

    private final class Feed: @unchecked Sendable {
        var next: [MemoryWatch.Sample?] = []
        func read() -> MemoryWatch.Sample? { next.isEmpty ? nil : next.removeFirst() }
    }

    private func sample(_ footprintMb: UInt64, _ availableMb: UInt64) -> MemoryWatch.Sample {
        MemoryWatch.Sample(footprint: footprintMb * Self.mb, available: availableMb * Self.mb)
    }

    func testItKeepsThePeakFootprintAndTheLowestHeadroom() {
        let feed = Feed()
        feed.next = [sample(300, 2_000), sample(900, 1_200), sample(600, 1_500), sample(400, 1_900)]
        let watch = MemoryWatch(read: feed.read)
        watch.begin()
        watch.sample()
        watch.sample()
        let reading = watch.end()
        XCTAssertEqual(reading.peakFootprint, 900 * Self.mb)
        XCTAssertEqual(reading.lowestAvailable, 1_200 * Self.mb)
        XCTAssertEqual(reading.samples, 4)
    }

    func testBeginStartsAFreshReading() {
        let feed = Feed()
        feed.next = [sample(900, 100), sample(900, 100), sample(200, 1_000), sample(250, 900)]
        let watch = MemoryWatch(read: feed.read)
        watch.begin()
        _ = watch.end()
        watch.begin()
        let second = watch.end()
        XCTAssertEqual(second.peakFootprint, 250 * Self.mb, "a second export must not inherit the first one's peak")
        XCTAssertEqual(second.lowestAvailable, 900 * Self.mb)
        XCTAssertEqual(second.samples, 2)
    }

    func testAPlatformWithNoLimitReportsNoHeadroomRatherThanZero() {
        let feed = Feed()
        feed.next = [sample(300, 0), sample(500, 0)]
        let watch = MemoryWatch(read: feed.read)
        watch.begin()
        let reading = watch.end()
        XCTAssertEqual(reading.peakFootprint, 500 * Self.mb)
        XCTAssertNil(reading.lowestAvailable, "0 means 'not reported' (the simulator), never 'no memory left'")
    }

    func testARefusedReadLeavesTheReadingAlone() {
        let feed = Feed()
        feed.next = [sample(300, 800), nil]
        let watch = MemoryWatch(read: feed.read)
        watch.begin()
        let reading = watch.end()
        XCTAssertEqual(reading.peakFootprint, 300 * Self.mb)
        XCTAssertEqual(reading.samples, 1)
    }

    func testTheLogLineIsCountsAndFixedWords() {
        let line = RecapExportJob.memoryLine(MemoryWatch.Reading(
            peakFootprint: 812 * Self.mb, lowestAvailable: 1_204 * Self.mb, samples: 7_460
        ))
        XCTAssertEqual(line, "peak 812 MB · lowest headroom 1204 MB · 7460 samples")
        let simulator = RecapExportJob.memoryLine(MemoryWatch.Reading(
            peakFootprint: 812 * Self.mb, lowestAvailable: nil, samples: 3
        ))
        XCTAssertEqual(simulator, "peak 812 MB · lowest headroom n/a · 3 samples")
    }

    func testTheRealReaderSeesThisProcess() throws {
        let now = try XCTUnwrap(MemoryWatch.current(), "task_info(TASK_VM_INFO) refused")
        XCTAssertGreaterThan(now.footprint, 1 * Self.mb, "a running test host holds more than a megabyte")
    }
}
