import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The render loop's pipeline across station boundaries, and its frame
/// filter** (`Docs/handoff-export-performance.md` §7).
///
/// One worker pool now serves the whole film rather than one per station, and
/// `renderFrames(only:)` skips frames nobody will use. Neither may change a
/// pixel: a frame that is rendered must be the frame a full, one-station-at-a-
/// time render would have produced, delivered in film order.
final class RecapRenderPipelineTests: RecapRenderTestCase {
    /// The Perth replay with its stops: every stop beat opens its own station
    /// (`RecapSnapshotStations.splitFrames`), so the film has several — the
    /// boundary is the thing under test.
    private struct Fixture {
        let loop: RecapRenderLoop
        let provider: CountingProvider
        let frames: Int
    }

    private func multiStationLoop() throws -> Fixture {
        let config = exportConfig(targetDurationS: 4, fps: 5, keyframeIntervalFrames: 3)
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let route = engine.segments.flatMap(\.points).map { RecapCoordinate(lat: $0.lat, lon: $0.lon) }
        let stops = engine.stops.enumerated().map { index, stop in
            RecapTrip.Stop(
                coordinate: RecapCoordinate(lat: stop.lat, lon: stop.lon),
                name: "Stop \(index + 1)", dayLabel: "Day 1", detail: nil, photos: [], dwellS: config.stopHoldS
            )
        }
        let trip = RecapTrip(
            route: route, stops: stops, title: "Perth", subtitle: "Day 1", endCardFigures: [], shareURL: ""
        )
        let timeline = try makeTimeline(trip, config: config)
        let provider = CountingProvider()
        let loop = RecapRenderLoop(
            timeline: timeline, compositor: makeCompositor(timeline), provider: provider, config: config
        )
        XCTAssertGreaterThan(loop.stations.count, 2, "the fixture must cross station boundaries")
        return Fixture(loop: loop, provider: provider, frames: timeline.frameCount)
    }

    private func render(
        _ loop: RecapRenderLoop, only wanted: (Int) -> Bool = { _ in true }
    ) async throws -> [(frame: Int, pixels: Data)] {
        var out: [(Int, Data)] = []
        try await loop.renderFrames(only: wanted) { frame, image in
            out.append((frame, try XCTUnwrap(image.dataProvider?.data as Data?)))
            return true
        }
        return out
    }

    func testEveryFrameIsDeliveredInFilmOrderAcrossStations() async throws {
        let fixture = try multiStationLoop()
        let (loop, frames) = (fixture.loop, fixture.frames)
        let delivered = try await render(loop).map(\.frame)
        XCTAssertEqual(delivered, Array(0..<frames))
    }

    func testFilteredFramesArePixelIdenticalToAFullRender() async throws {
        let loop = try multiStationLoop().loop
        let full = Dictionary(uniqueKeysWithValues: try await render(loop).map { ($0.frame, $0.pixels) })
        let even = try await render(loop) { $0.isMultiple(of: 2) }

        XCTAssertEqual(even.map(\.frame), full.keys.sorted().filter { $0.isMultiple(of: 2) })
        for (frame, pixels) in even {
            XCTAssertEqual(pixels, full[frame], "frame \(frame) must not change because its neighbours were skipped")
        }
    }

    func testAStationWithNoWantedFrameIsNeverFetched() async throws {
        let fixture = try multiStationLoop()
        let (loop, provider) = (fixture.loop, fixture.provider)
        let firstStation = try XCTUnwrap(loop.stations.first).frames
        let delivered = try await render(loop) { firstStation.contains($0) }

        XCTAssertEqual(delivered.map(\.frame), Array(firstStation))
        XCTAssertEqual(provider.requestCount, 1, "only the first station has a wanted frame")
    }

    func testCancellingMidFilmStopsAcrossStations() async throws {
        let fixture = try multiStationLoop()
        let (loop, frames) = (fixture.loop, fixture.frames)
        let stopAfter = try XCTUnwrap(loop.stations.first).frames.upperBound
        XCTAssertLessThan(stopAfter, frames - 1)

        var delivered: [Int] = []
        try await loop.renderFrames { frame, _ in
            delivered.append(frame)
            return frame < stopAfter
        }
        XCTAssertEqual(delivered, Array(0...stopAfter), "the loop stops right after the consumer declines")
    }
}
