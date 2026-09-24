import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The pill names the town on the road** (ADR 2026-09-24 (c), Chiu:
/// *「也把地名加進 pill」*). Parked, it names the stop, as it always did; between
/// stops it names the town of the most recent stop reached, and turns over on
/// arrival — the day counter's rule.
final class LinearTimelineHUDPlaceTests: LinearTimelineTestCase {
    /// Three stops: two in one town, the third in the next.
    private func trip(config: TrackingConfig.Export) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let towns = ["Perth", "Perth", "Fremantle"]
        let stops = (0..<3).map { index -> RecapTrip.Stop in
            RecapTrip.Stop(
                coordinate: route[(index + 1) * 9],
                name: "Stop \(index + 1)", dayLabel: "Day 1", detail: nil,
                photos: (0..<3).map { .asset("s\(index)-\($0)") },
                dwellS: deck.dwellS(photoCount: 3),
                locality: towns[index]
            )
        }
        return RecapTrip(
            route: route, stops: stops, title: "Sample", subtitle: "3 stops",
            endCardFigures: [RecapEndCardFigure(value: "3", label: "STOPS")]
        )
    }

    private func places(_ timeline: LinearTimeline) -> [(time: Double, place: String?)] {
        var samples: [(time: Double, place: String?)] = []
        var time = 0.0
        while time <= timeline.durationS {
            for content in timeline.overlayContents(atTime: time) {
                if case let .hud(_, place, _) = content { samples.append((time, place)) }
            }
            time += 1.0 / 30
        }
        return samples
    }

    func testThePillNamesTheTownBetweenStopsAndTheStopWhenParked() throws {
        let config = exportConfig()
        let samples = places(try fixedTimeline(trip(config: config), config))
        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.allSatisfy { $0.place != nil }, "the pill always says where, with no crossing")

        let stopNames: Set<String> = ["Stop 1", "Stop 2", "Stop 3"]
        XCTAssertEqual(Set(samples.compactMap { $0.place }.filter(stopNames.contains)), stopNames)
        XCTAssertEqual(
            Set(samples.compactMap { $0.place }.filter { !stopNames.contains($0) }), ["Perth", "Fremantle"]
        )

        // The town turns over on arrival at Stop 3, never out on the road before it.
        let arrival = try XCTUnwrap(samples.first { $0.place == "Stop 3" }).time
        for sample in samples where sample.time < arrival {
            XCTAssertNotEqual(sample.place, "Fremantle", "the next town was named before arriving, t=\(sample.time)")
        }
        for sample in samples where sample.time > arrival && sample.place != "Stop 3" {
            XCTAssertEqual(sample.place, "Fremantle", "t=\(sample.time)")
        }
    }
}
