import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **Where the journey set out is named over the opening** (Chiu 2026-11-03).
/// A short film that drops the trip's first stop opened on an unmarked point,
/// while the map already named a town the trip reaches later, and the HUD gave
/// the first stop's day and town before the car had left.
final class LinearTimelineDepartureTests: LinearTimelineTestCase {
    private let region = RecapBounds(minLat: -33, minLon: 115, maxLat: -31, maxLon: 117)

    /// Two stops a day after the departure, and the departure itself at the
    /// route's first vertex. `stopVertices` places the stops.
    private func trip(
        departure: Bool = true, photos: Int = 3, stopVertices: [Int] = [18, 36], config: TrackingConfig.Export
    ) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let stops = stopVertices.enumerated().map { index, vertex in
            RecapTrip.Stop(
                coordinate: route[vertex], name: "Stop \(index + 1)", dayLabel: "Day 2",
                photos: (0..<photos).map { .asset("s\(index)-\($0)") },
                dwellS: photos > 0 ? deck.dwellS(photoCount: photos) : config.stopHoldS, locality: "Inland"
            )
        }
        let start = RecapTrip.Stop(
            coordinate: route[0], name: "Harbour", dayLabel: "Day 1", dwellS: config.stopHoldS, locality: "Portville"
        )
        return RecapTrip(
            legs: [RecapTrip.Leg(coordinates: route, mode: .drive, provenance: .recorded)],
            stops: stops, title: "Sample", subtitle: "", endCardFigures: [],
            departure: departure ? start : nil
        )
    }

    private func timeline(_ trip: RecapTrip, _ config: TrackingConfig.Export) throws -> LinearTimeline {
        try XCTUnwrap(LinearTimeline(trip: trip, config: config, establishing: region))
    }

    /// Every frame's contents, at the film's own rate.
    private func frames(_ line: LinearTimeline) -> [(time: Double, contents: [OverlayContent])] {
        (0..<line.frameCount).map { frame in
            let time = Double(frame) / 30
            return (time, line.overlayContents(atTime: time))
        }
    }

    private func departureLabels(_ line: LinearTimeline) -> [(time: Double, opacity: Double)] {
        frames(line).compactMap { frame in
            for content in frame.contents {
                if case let .stopLabel(name, _, _, opacity) = content, name == "Harbour" { return (frame.time, opacity) }
            }
            return nil
        }
    }

    private struct HUD {
        let time: Double
        let day: String
        let place: String?
    }

    private func huds(_ line: LinearTimeline) -> [HUD] {
        frames(line).compactMap { frame in
            for content in frame.contents {
                if case let .hud(day, place, _) = content { return HUD(time: frame.time, day: day, place: place) }
            }
            return nil
        }
    }

    func testTheDepartureIsNamedWhileTheCarWaitsAndGoneOnceItLeaves() throws {
        let config = exportConfig()
        let line = try timeline(trip(config: config), config)
        XCTAssertGreaterThan(line.openingS, 0, "precondition: a film with an opening")
        let labels = departureLabels(line)
        let first = try XCTUnwrap(labels.first, "the departure was never named")
        XCTAssertGreaterThanOrEqual(first.time, config.titleCardS, "named under the title card")
        let last = try XCTUnwrap(labels.last)
        XCTAssertLessThan(last.time, line.journeyStartS + config.deckZoomS, "still named after the car left")
        let opacities = labels.map(\.opacity)
        let peak = try XCTUnwrap(opacities.indices.max { opacities[$0] < opacities[$1] })
        XCTAssertGreaterThan(opacities[peak], 0.99, "never fully up")
        // Up once and down once: no flicker while the car waits.
        for index in opacities.indices.dropFirst() {
            let step = opacities[index] - opacities[index - 1]
            XCTAssertTrue(index <= peak ? step >= -1e-9 : step <= 1e-9, "flickered at t=\(labels[index].time)")
        }
    }

    func testTheHUDGivesTheDeparturesDayAndTownUntilTheFirstStop() throws {
        let config = exportConfig()
        let samples = huds(try timeline(trip(config: config), config))
        let arrival = try XCTUnwrap(samples.first { $0.place == "Stop 1" }, "the first stop never came").time
        let before = samples.filter { $0.time < arrival }
        XCTAssertFalse(before.isEmpty)
        for sample in before {
            XCTAssertEqual(sample.day, "Day 1", "t=\(sample.time)")
            XCTAssertEqual(sample.place, "Portville", "t=\(sample.time)")
        }
        XCTAssertTrue(samples.filter { $0.time >= arrival }.allSatisfy { $0.day == "Day 2" })
    }

    func testAFilmWithoutADepartureIsUnchanged() throws {
        let config = exportConfig()
        let line = try timeline(trip(departure: false, config: config), config)
        XCTAssertTrue(departureLabels(line).isEmpty)
        let samples = huds(line)
        let arrival = try XCTUnwrap(samples.first { $0.place == "Stop 1" }).time
        XCTAssertTrue(samples.filter { $0.time < arrival }.allSatisfy { $0.day == "Day 2" && $0.place == "Inland" })
    }

    /// A route-only film names no stop on the map, so not its departure either;
    /// its HUD still starts on the departure's day.
    func testARouteOnlyFilmDrawsNoDepartureLabel() throws {
        let config = exportConfig()
        let line = try timeline(trip(photos: 0, config: config), config)
        XCTAssertTrue(departureLabels(line).isEmpty)
        XCTAssertEqual(huds(line).first?.day, "Day 1")
    }

    /// A stop held where the car starts names the start itself; two labels on one
    /// point would cover each other.
    func testAStopAtTheStartNamesItInsteadOfTheDeparture() throws {
        let config = exportConfig()
        let line = try timeline(trip(stopVertices: [0, 36], config: config), config)
        XCTAssertTrue(departureLabels(line).isEmpty)
    }
}
