import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **The film names the trip's own towns on the map** (Chiu 2026-10-02, ADR
/// file 2026-10-02): which towns, when, and which name gives way when two meet.
final class RecapPlaceNamesTests: LinearTimelineTestCase {
    private func stop(_ lat: Double, town: String?, part: String? = nil, dwellS: Double = 6) -> RecapTrip.Stop {
        RecapTrip.Stop(
            coordinate: RecapCoordinate(lat: lat, lon: 115.75), name: "Stop", dayLabel: "Day 1",
            dwellS: dwellS, locality: town, subLocality: part
        )
    }

    /// `sampleTrip` with a town on every stop: two stops in A, one in B. The
    /// last stop has no name of its own, so it is called by its town — "B".
    private func tripWithTowns(_ config: TrackingConfig.Export) -> RecapTrip {
        let sample = sampleTrip(photoCounts: [1, 1, 1], config: config)
        let towns = ["A", "A", "B"]
        let stops = zip(sample.stops, towns).enumerated().map { index, pair in
            RecapTrip.Stop(
                coordinate: pair.0.coordinate, name: index == 2 ? "B" : pair.0.name, dayLabel: pair.0.dayLabel,
                photos: pair.0.photos, dwellS: pair.0.dwellS, locality: pair.1
            )
        }
        return RecapTrip(
            route: sample.route, stops: stops, title: sample.title, subtitle: sample.subtitle,
            endCardFigures: sample.endCardFigures
        )
    }

    private func towns(in contents: [OverlayContent]) -> (names: [RecapPlaceName], opacity: Double)? {
        for case let .placeNames(names, opacity) in contents { return (names, opacity) }
        return nil
    }

    /// One name per town, on the stop nearest the middle of its stops, and only
    /// towns the film's stops are in: a stop the geocoder gave no town names
    /// nothing. On a stop, not at the middle itself (restated 2026-10-02): the
    /// middle of two stops on a curved coast is in the sea.
    func testEachTownIsNamedOnceAtTheStopNearestTheMiddleOfItsStops() {
        let names = LinearTimeline.placeNames(of: [
            stop(-32.0, town: "A"), stop(-32.2, town: nil), stop(-32.4, town: "B"), stop(-32.1, town: "A"),
            stop(-32.3, town: ""), stop(-32.16, town: "A")
        ])
        XCTAssertEqual(names.map(\.name), ["A", "B"])
        XCTAssertEqual(names[0].coordinate.lat, -32.1, accuracy: 1e-9)
        XCTAssertEqual(names[1].coordinate.lat, -32.4, accuracy: 1e-9)
    }

    /// **A journey that never leaves one town is named by the town's parts**
    /// (Chiu 2026-10-02, #183: 「標更細的地名」). Miyakojima is one municipality:
    /// the film had one name, and its close frames none. A stop the geocoder
    /// gave no part keeps the town.
    func testAJourneyInOneTownIsNamedByItsParts() {
        let names = LinearTimeline.placeNames(of: [
            stop(24.80, town: "Miyakojima", part: "Hirara"), stop(24.82, town: "Miyakojima", part: "Hirara"),
            stop(24.815, town: "Miyakojima", part: "Hirara"),
            stop(24.83, town: "Miyakojima", part: "Irabu"), stop(24.74, town: "Miyakojima", part: nil),
            stop(24.72, town: nil, part: "Gusukube")
        ])
        XCTAssertEqual(Set(names.map(\.name)), ["Hirara", "Irabu", "Miyakojima", "Gusukube"])
        XCTAssertEqual(names.first { $0.name == "Hirara" }?.coordinate.lat ?? 0, 24.815, accuracy: 1e-9)
    }

    /// One part is no finer than the town, and less known: the town stays.
    func testOnePartIsNotANameOfItsOwn() {
        let names = LinearTimeline.placeNames(of: [
            stop(24.80, town: "Miyakojima", part: "Hirara"), stop(24.82, town: "Miyakojima", part: "Hirara")
        ])
        XCTAssertEqual(names.map(\.name), ["Miyakojima"])
    }

    /// A journey between towns is named by its towns, whatever parts they have:
    /// its frame is sized to the drives between them.
    func testAJourneyBetweenTownsKeepsItsTowns() {
        let names = LinearTimeline.placeNames(of: [
            stop(25.03, town: "Taipei", part: "Xinyi"), stop(25.05, town: "Taipei", part: "Zhongshan"),
            stop(24.75, town: "Yilan", part: "Jiaoxi")
        ])
        XCTAssertEqual(Set(names.map(\.name)), ["Taipei", "Yilan"])
    }

    /// **Each side of a flight is its own journey.** The airport the trip left
    /// from is in another town, and the island is still one town.
    func testTheTownLeftByAirDoesNotCountAgainstTheIsland() {
        let stops = [
            stop(25.08, town: "Dayuan", part: "Puxin"),
            stop(24.80, town: "Miyakojima", part: "Hirara"), stop(24.83, town: "Miyakojima", part: "Irabu")
        ]
        XCTAssertEqual(Set(LinearTimeline.placeNames(of: stops, journeys: [0, 1, 1]).map(\.name)),
                       ["Dayuan", "Hirara", "Irabu"])
        XCTAssertEqual(Set(LinearTimeline.placeNames(of: stops).map(\.name)), ["Dayuan", "Miyakojima"],
                       "as one journey these are two towns")
    }

    /// Where two names would overlap, the town the film stays in longest is the
    /// one drawn — so it comes first, whatever order the trip visits them in.
    func testTheTownTheFilmStaysInLongestComesFirst() {
        let names = LinearTimeline.placeNames(of: [
            stop(-32.0, town: "Passed", dwellS: 6), stop(-32.1, town: "Stayed", dwellS: 10),
            stop(-32.2, town: "Stayed", dwellS: 10), stop(-32.3, town: "Later", dwellS: 6)
        ])
        XCTAssertEqual(names.map(\.name), ["Stayed", "Passed", "Later"])
    }

    /// The names are on the map for the body of the film and the end reveal,
    /// directly over the trail and under everything else — never over the title
    /// card or the end card, which own their seconds.
    func testTheNamesAreUpForTheBodyAndNeverOverACard() throws {
        let config = exportConfig()
        let line = try fixedTimeline(tripWithTowns(config), config)
        XCTAssertNil(towns(in: line.overlayContents(atTime: config.titleCardS / 2)), "over the title card")
        XCTAssertNil(towns(in: line.overlayContents(atTime: line.durationS - config.endCardS / 2)), "over the end card")

        let middle = line.overlayContents(atTime: line.durationS / 2)
        let shown = try XCTUnwrap(towns(in: middle))
        XCTAssertEqual(shown.names.map(\.name).sorted(), ["A", "B"])
        XCTAssertEqual(shown.opacity, 1, accuracy: 1e-9)
        guard case .placeNames = middle[1] else { return XCTFail("not directly over the trail: \(middle)") }
        let reveal = line.overlayContents(atTime: line.durationS - config.endCardS - 0.1)
        XCTAssertNotNil(towns(in: reveal), "the revealed route lost its names")
    }

    /// **One word is not set twice in one frame.** A stop with no landmark name
    /// is called by its town; while the film presents it, the town's own name
    /// yields to the stop's, and comes back on the road. The other towns keep
    /// theirs throughout.
    func testATownsNameYieldsWhileAStopIsPresentedUnderIt() throws {
        let config = exportConfig()
        let line = try fixedTimeline(tripWithTowns(config), config)
        let hold = try XCTUnwrap(line.holds.first { $0.stopIndex == 2 })
        func opacity(of name: String, at time: Double) throws -> Double {
            try XCTUnwrap(try XCTUnwrap(towns(in: line.overlayContents(atTime: time))).names.first { $0.name == name })
                .opacity
        }
        let presented = (hold.startS + hold.endS) / 2
        XCTAssertLessThan(try opacity(of: "B", at: presented), 0.01, "the stop and its town are both set as B")
        XCTAssertEqual(try opacity(of: "A", at: presented), 1, accuracy: 1e-9)
        let onTheRoad = hold.startS - 0.5
        XCTAssertNil(line.presentedStopName(atTime: onTheRoad), "t=\(onTheRoad) is not on the road in this fixture")
        XCTAssertEqual(try opacity(of: "B", at: onTheRoad), 1, accuracy: 1e-9)
    }

    /// A trip whose stops have no towns draws no names — the film it was.
    func testATripWithoutTownsHasNoNames() throws {
        let config = exportConfig()
        let line = try fixedTimeline(sampleTrip(photoCounts: [1, 1, 1], config: config), config)
        for frame in stride(from: 0, to: line.frameCount, by: 7) {
            XCTAssertNil(towns(in: line.overlayContents(atTime: Double(frame) / Double(config.fps))))
        }
    }

    /// Names are kept in order: a later one that meets an earlier one is not
    /// drawn, and one that meets only a dropped name is.
    func testAnEarlierNameWinsWhereTwoMeet() {
        let first = CGRect(x: 0, y: 0, width: 100, height: 40)
        let meetsFirst = CGRect(x: 90, y: 10, width: 100, height: 40)
        let meetsOnlyTheDropped = CGRect(x: 185, y: 10, width: 100, height: 40)
        let apart = CGRect(x: 0, y: 200, width: 100, height: 40)
        XCTAssertEqual(RecapOverlayRenderer.uncrowded([first, meetsFirst, meetsOnlyTheDropped, apart]), [0, 2, 3])
    }

    /// A name whose town is near the edge of the frame is slid inside it whole,
    /// and one already inside is not moved.
    func testANameNearTheEdgeIsHeldInsideTheFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let inside = CGRect(x: 400, y: 900, width: 200, height: 44)
        XCTAssertEqual(RecapOverlayRenderer.held(inside, inside: frame), inside)
        let offTheLeft = CGRect(x: -120, y: 900, width: 200, height: 44)
        XCTAssertEqual(RecapOverlayRenderer.held(offTheLeft, inside: frame).minX, 0)
        let offTheBottom = CGRect(x: 1000, y: -30, width: 200, height: 44)
        let held = RecapOverlayRenderer.held(offTheBottom, inside: frame)
        XCTAssertEqual(held.maxX, 1080)
        XCTAssertEqual(held.minY, 0)
    }

    /// A long name of several words is set on its two most even lines; a short
    /// one, or one with nowhere to break, stays on one.
    func testALongNameBreaksIntoTwoEvenLines() {
        let width: (String) -> CGFloat = { CGFloat($0.count) * 10 }
        XCTAssertEqual(
            RecapOverlayRenderer.lines(of: "Aoraki Mount Cook National Park", maxWidth: 200, width: width),
            ["Aoraki Mount Cook", "National Park"]
        )
        XCTAssertEqual(RecapOverlayRenderer.lines(of: "Lake Tekapo", maxWidth: 200, width: width), ["Lake Tekapo"])
        XCTAssertEqual(
            RecapOverlayRenderer.lines(of: "Kirkjubæjarklaustur", maxWidth: 100, width: width), ["Kirkjubæjarklaustur"]
        )
    }
}
