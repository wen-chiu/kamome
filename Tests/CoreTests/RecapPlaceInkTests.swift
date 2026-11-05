import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **The film inks each of the trip's towns as the car reaches it** (Chiu
/// 2026-10-29, ADR 2026-10-29-the-film-inks-each-town-the-car-reaches): when a
/// town is reached, how long its ink stays, and that nothing else in the film
/// moves for it. Every place here is made up (§0).
final class RecapPlaceInkTests: LinearTimelineTestCase {
    /// `sampleTrip` with two stops in North and one in South, unless told otherwise.
    private func trip(
        _ config: TrackingConfig.Export, photoCounts: [Int] = [1, 1, 1], towns: [String] = ["North", "North", "South"]
    ) -> RecapTrip {
        let sample = sampleTrip(photoCounts: photoCounts, config: config)
        let stops = zip(sample.stops, towns).map { stop, town in
            RecapTrip.Stop(
                coordinate: stop.coordinate, name: stop.name, dayLabel: stop.dayLabel,
                photos: stop.photos, dwellS: stop.dwellS, locality: town
            )
        }
        return RecapTrip(
            route: sample.route, stops: stops, title: sample.title, subtitle: sample.subtitle,
            endCardFigures: sample.endCardFigures
        )
    }

    private func names(_ line: LinearTimeline, at time: Double) -> [RecapPlaceName] {
        for case let .placeNames(names, _) in line.overlayContents(atTime: time) { return names }
        return []
    }

    private func ink(of town: String, _ line: LinearTimeline, at time: Double) -> Double? {
        names(line, at: time).first { $0.name == town }?.ink
    }

    private func frameTimes(_ line: LinearTimeline, fps: Int) -> [Double] {
        (0..<line.frameCount).map { Double($0) / Double(fps) }
    }

    /// Un-inked before the car reaches it; drawn over `place_name_ink_draw_s`,
    /// finishing as its first stop begins its lead-in; inked from then on,
    /// through the end reveal, to the last frame names are drawn on.
    func testATownIsInkedAsItsFirstStopsLeadInBeginsAndStaysInked() throws {
        let config = exportConfig(placeNameInkDrawS: 0.6)
        let line = try fixedTimeline(trip(config), config)
        let hold = try XCTUnwrap(line.holds.first { $0.stopIndex == 2 })
        XCTAssertEqual(line.placeInks()["South"]?.path, .beforeTheLeadIn, "precondition: the road in fits the pen")

        XCTAssertLessThan(line.leadLabelOpacity(
            atTime: hold.startS, hold: hold, deck: line.deckWindow(hold)
        ), 0.001, "the lead-in has not begun")
        XCTAssertEqual(try XCTUnwrap(ink(of: "South", line, at: hold.startS - 0.3)), 0.5, accuracy: 1e-6)
        let endOfNames = line.durationS - config.endCardS
        for time in frameTimes(line, fps: config.fps) where time >= config.titleCardS && time < endOfNames {
            let expected: Double? = time < hold.startS - 0.6 ? 0 : time >= hold.startS ? 1 : nil
            guard let expected else { continue }
            XCTAssertEqual(ink(of: "South", line, at: time), expected, "t=\(time)")
        }
    }

    /// **A town the film never presents is never inked.** With the photo cards
    /// off the film presents no stop (`quietStop`), so no town is reached —
    /// the names are still there, as a map's are.
    func testATownNeverReachedIsNeverInked() throws {
        let config = exportConfig(placeNameInkDrawS: 0.6)
        let line = try fixedTimeline(trip(config, photoCounts: [0, 0, 0]), config)
        XCTAssertTrue(line.placeInks().isEmpty)
        var named = 0
        for time in frameTimes(line, fps: config.fps) {
            let shown = names(line, at: time)
            named += shown.count
            XCTAssertTrue(shown.allSatisfy { $0.ink == 0 }, "t=\(time)")
        }
        XCTAssertGreaterThan(named, 0, "precondition: the towns are named")
    }

    /// **The road in too short for the pen**: the ink draws as the town's name
    /// comes back, once its first stop has finished presenting — never under
    /// the stop's own card.
    func testWhenTheRoadInIsTooShortTheInkDrawsAsTheNameReturns() throws {
        let towns = ["North", "Middle", "South"]
        let probe = try fixedTimeline(trip(exportConfig(), towns: towns), exportConfig())
        let before = try XCTUnwrap(probe.holds.first { $0.stopIndex == 0 })
        let hold = try XCTUnwrap(probe.holds.first { $0.stopIndex == 1 })
        let drawS = hold.startS - before.endS + 0.2
        let config = exportConfig(placeNameInkDrawS: drawS)
        let line = try fixedTimeline(trip(config, towns: towns), config)

        let returns = line.deckWindow(hold).end
        XCTAssertEqual(line.placeInks()["Middle"], .init(startS: returns, path: .asTheNameReturns))
        XCTAssertEqual(try XCTUnwrap(ink(of: "Middle", line, at: returns - 0.01)), 0)
        XCTAssertEqual(try XCTUnwrap(ink(of: "Middle", line, at: returns + drawS / 2)), 0.5, accuracy: 1e-6)
        XCTAssertLessThan(try XCTUnwrap(line.presentedStopName(atTime: returns + 0.01)).opacity, 0.001,
                          "the stop is still presenting itself")
    }

    /// **Each journey's towns are reached on their own side of a crossing**:
    /// an island the trip never leaves is named, and reached, by its parts —
    /// and nothing on it is inked before the crossing that lands there.
    func testEachJourneysTownsAreReachedOnTheirOwnSideOfACrossing() throws {
        let config = try shipped()
        let line = try XCTUnwrap(LinearTimeline(trip: crossingTrip, config: config, locale: Locale(identifier: "en")))
        let crossing = try XCTUnwrap(line.path.crossingBeatWindowsS.first, "precondition: the film flies")
        let inks = line.placeInks()
        XCTAssertEqual(Set(inks.keys).intersection(["West End", "East End", "Isle"]), ["West End", "East End"])
        for part in ["West End", "East End"] {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(inks[part]).startS, crossing.upperBound, part)
        }
    }

    /// **The film is exactly as long as it was.** The pen's time is taken out
    /// of nothing: every hold, every frame count and every camera frame is the
    /// same whatever `place_name_ink_draw_s` is.
    func testTheInkNeverChangesTheFilmsLengthOrItsCamera() throws {
        let made: [(RecapTrip, (Double) throws -> TrackingConfig.Export)] = [
            (trip(exportConfig()), { self.exportConfig(placeNameInkDrawS: $0) }),
            (crossingTrip, { try self.shipped(inkDrawS: $0) })
        ]
        for (trip, config) in made {
            let lines = try [0, 0.6, 4].map { drawS in
                try XCTUnwrap(LinearTimeline(trip: trip, config: try config(drawS), locale: Locale(identifier: "en")))
            }
            for line in lines.dropFirst() {
                XCTAssertEqual(line.durationS, lines[0].durationS)
                XCTAssertEqual(line.frameCount, lines[0].frameCount)
                XCTAssertEqual(line.holds, lines[0].holds)
                for time in stride(from: 0, to: line.durationS, by: 0.25) {
                    XCTAssertEqual(line.cameraFrame(atTime: time), lines[0].cameraFrame(atTime: time))
                }
            }
        }
    }

    /// **Only the ink moves.** Title card, end card, the stop's own label, the
    /// photo deck, the HUD and the names' own fades are what they were; take
    /// the ink off and every frame's overlays are identical.
    func testNothingButTheInkChanges() throws {
        let plain = exportConfig()
        let inked = exportConfig(placeNameInkDrawS: 0.6)
        let before = try fixedTimeline(trip(plain), plain)
        let after = try fixedTimeline(trip(inked), inked)
        var inkedFrames = 0
        for time in frameTimes(after, fps: inked.fps) {
            let contents = after.overlayContents(atTime: time)
            if names(after, at: time).contains(where: { $0.ink > 0 }) { inkedFrames += 1 }
            XCTAssertEqual(contents.map(Self.withoutInk), before.overlayContents(atTime: time).map(Self.withoutInk))
        }
        XCTAssertGreaterThan(inkedFrames, 0, "precondition: something was inked")
    }

    private static func withoutInk(_ content: OverlayContent) -> OverlayContent {
        guard case let .placeNames(names, opacity) = content else { return content }
        return .placeNames(names.map { RecapPlaceName(name: $0.name, coordinate: $0.coordinate, opacity: $0.opacity) },
                           opacity: opacity)
    }

    /// The shipped config, with the pen's time replaced when one is given.
    private func shipped(inkDrawS: Double? = nil) throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        guard let inkDrawS else { return try TrackingConfigLoader.load(contentsOf: url).export }
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var export = try XCTUnwrap(json["export"] as? [String: Any])
        export["place_name_ink_draw_s"] = inkDrawS
        json["export"] = export
        return try TrackingConfigLoader.load(from: JSONSerialization.data(withJSONObject: json)).export
    }

    /// A made-up grid on the equator: a short drive round Port Town, a flight
    /// over open water, and a drive round Isle, whose stops are in two parts.
    private var crossingTrip: RecapTrip {
        let stops = [
            (0.00, 10.00, "Port Town", ""), (0.05, 10.05, "Port Town", ""), (0.00, 13.00, "Isle", "West End"),
            (0.04, 13.06, "Isle", "West End"), (0.00, 13.12, "Isle", "East End")
        ].enumerated().map { index, place -> RecapTrip.Stop in
            RecapTrip.Stop(
                coordinate: RecapCoordinate(lat: place.0, lon: place.1), name: "Stop \(index)", dayLabel: "Day 1",
                photos: [.asset("a\(index)"), .asset("b\(index)")], dwellS: 3600,
                locality: place.2, subLocality: place.3
            )
        }
        let places = stops.map(\.coordinate)
        let legs = zip(places, places.dropFirst()).enumerated().map { index, pair in
            RecapTrip.Leg(
                coordinates: index == 1 ? [pair.0, pair.1] : (0...20).map { step in
                    let fraction = Double(step) / 20
                    return RecapCoordinate(lat: pair.0.lat + (pair.1.lat - pair.0.lat) * fraction,
                                           lon: pair.0.lon + (pair.1.lon - pair.0.lon) * fraction)
                },
                mode: .drive, provenance: .reconstructed, isCrossing: index == 1
            )
        }
        return RecapTrip(
            legs: legs, stops: stops, title: "T", subtitle: "", endCardFigures: [],
            everyLegRoutabilityEstablished: true
        )
    }
}
