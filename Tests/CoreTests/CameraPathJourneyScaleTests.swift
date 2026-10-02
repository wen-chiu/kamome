import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The journey's frame nearly holds its widest drive between two towns** (ADR
/// file 2026-10-02, amending 2026-09-28 item 1).
///
/// Chiu's New Zealand film was framed at 130 km at the desk and at about 60 km
/// on his phone (「中間行程的時候拉太近了」). The scale was a median over stops whose
/// frames come in two sizes — a basin of towns 50 km apart, and the drives in and
/// out of it — and a median belongs to whichever size has one stop more. These
/// pin the rule that replaced it, on the shipped tunables.
final class CameraPathJourneyScaleTests: XCTestCase {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")

    private func shipped() throws -> TrackingConfig.Export {
        try TrackingConfigLoader.load(contentsOf: Self.configURL).export
    }

    /// One road trip with a basin of close towns in it.
    private struct Trip {
        let route: [CameraPath.Point]
        let stops: [CameraPath.Point]
        let towns: [String]
        /// The basin's first and last town.
        let basin: (first: CameraPath.Point, last: CameraPath.Point)
    }

    /// Four towns 150 km apart, then three 20 km apart, along one road.
    /// `basinStops` is how many stops the middle basin town gets — photo stops a
    /// few hundred metres apart; every other town has one.
    private func roadTripWithABasin(basinStops: Int) -> Trip {
        let degreesPerKm = 1 / 111.32
        func point(km: Double) -> CameraPath.Point { CameraPath.Point(lat: 0, lon: km * degreesPerKm) }
        let basin = [600.0, 620, 640].map { point(km: $0) }
        let middle = (0..<basinStops).map { point(km: 620 + Double($0) * 0.3) }
        return Trip(
            route: stride(from: 0.0, through: 640, by: 1).map { point(km: $0) },
            stops: [0.0, 150, 300, 450].map { point(km: $0) } + [basin[0]] + middle + [basin[2]],
            towns: ["S1", "S2", "S3", "S4", "B1"] + middle.map { _ in "B2" } + ["B3"],
            basin: (basin[0], basin[2])
        )
    }

    private func journeyScaleM(_ trip: Trip, config: TrackingConfig.Export) throws -> Double {
        let line = try XCTUnwrap(CameraPath(
            route: trip.route, stops: trip.stops, config: config, totalDurationS: 60, stopPlaces: trip.towns
        ))
        XCTAssertTrue(line.reframeArcs.isEmpty, "zoomed in and out at \(line.areaSpansM.map { Int($0) }) m")
        return try XCTUnwrap(line.areaSpansM.max())
    }

    /// **The frame is `journey_drive_fit` of the one that just holds the widest
    /// drive** — here 150 km between two towns on one east–west road, so the
    /// frame that holds it is 150 km wide (Chiu 2026-10-02: 「可以167*0.9拉近」).
    func testTheFrameNearlyHoldsTheWidestDriveBetweenTwoTowns() throws {
        let config = try shipped()
        let trip = roadTripWithABasin(basinStops: 1)
        let widestM = Geo.distanceM(
            latA: trip.stops[0].lat, lonA: trip.stops[0].lon, latB: trip.stops[1].lat, lonB: trip.stops[1].lon
        )
        XCTAssertEqual(
            try journeyScaleM(trip, config: config), widestM * config.cameraContext.journeyDriveFit, accuracy: 1
        )
        XCTAssertLessThan(config.cameraContext.journeyDriveFit, 1, "the widest drive is no longer nearly fitted")
    }

    /// **One more stop in a town already visited never changes the film's scale
    /// by a zoom a viewer can read.** `opening_collapse_zoom_ratio` is the zoom
    /// too small to read — the question that key already answers for the opening,
    /// the crossing arcs and the area seams.
    func testOneMoreStopInATownDoesNotRescaleTheFilm() throws {
        let config = try shipped()
        for basinStops in 1...4 {
            let before = try journeyScaleM(roadTripWithABasin(basinStops: basinStops), config: config)
            let after = try journeyScaleM(roadTripWithABasin(basinStops: basinStops + 1), config: config)
            XCTAssertLessThan(
                max(before, after) / min(before, after), config.openingCollapseZoomRatio,
                "stop \(basinStops + 1) in one town moved the scale from \(Int(before)) m to \(Int(after)) m"
            )
        }
    }

    /// **The towns with the most stops do not set the scale alone.** With most of
    /// the film's stops in the basin, the frame is still readably wider than the
    /// one that just holds the basin: the drives count too.
    func testABasinOfCloseTownsDoesNotSetTheScaleAlone() throws {
        let config = try shipped()
        let trip = roadTripWithABasin(basinStops: 4)
        let scaleM = try journeyScaleM(trip, config: config)
        // The frame centred on the basin's end town that holds the other two.
        let basinM = 2 * Geo.distanceM(
            latA: trip.basin.first.lat, lonA: trip.basin.first.lon, latB: trip.basin.last.lat, lonB: trip.basin.last.lon
        )
        XCTAssertGreaterThan(scaleM, basinM * config.openingCollapseZoomRatio,
                             "the film is framed at the basin's own scale, \(Int(scaleM)) m")
    }

    /// **A trip of two towns has no journey scale**: one drive is a line between
    /// two places, and it is framed exactly as it is with no names at all — the
    /// rule every island film judged before 2026-10-02 was made under.
    func testATripOfTwoTownsIsFramedAsWithoutTowns() throws {
        let config = try shipped()
        let route = stride(from: 0.0, through: 151, by: 1).map { CameraPath.Point(lat: 0, lon: $0 / 111.32) }
        let stops = [route[0], route[1], route[150], route[151]]
        let named = try XCTUnwrap(CameraPath(
            route: route, stops: stops, config: config, totalDurationS: 60, stopPlaces: ["A", "A", "B", "B"]
        ))
        let unnamed = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config, totalDurationS: 60))
        XCTAssertGreaterThan(unnamed.areaSpansM.count, 1, "one area — this trip no longer tests the rule")
        XCTAssertEqual(named.areaSpansM, unnamed.areaSpansM)
    }

    /// **The drive to the airport does not frame the island.** A scale belongs to
    /// one journey; the town past a flight is in another. Here 200 km are driven
    /// between two towns before the flight, and three towns 30 km apart after it.
    func testAJourneyIsNotFramedByADriveOnTheOtherSideOfAFlight() throws {
        let config = try shipped()
        func point(km: Double, lon: Double) -> CameraPath.Point { CameraPath.Point(lat: 0, lon: lon + km / 111.32) }
        let home = stride(from: 0.0, through: 200, by: 1).map { point(km: $0, lon: 121) }
        let island = stride(from: 0.0, through: 60, by: 1).map { point(km: $0, lon: 125) }
        let line = try XCTUnwrap(CameraPath(
            route: home + island, stops: [home[0], home[200], island[0], island[30], island[60]], config: config,
            totalDurationS: 60, crossingVertexRanges: [200..<202], stopPlaces: ["Home", "Airport", "I1", "I2", "I3"]
        ))
        let islandDriveM = Geo.distanceM(latA: 0, lonA: island[0].lon, latB: 0, lonB: island[30].lon)
        XCTAssertEqual(
            try XCTUnwrap(line.areaSpansM.last), islandDriveM * config.cameraContext.journeyDriveFit, accuracy: 1,
            "the island is framed at \(line.areaSpansM.map { Int($0) }) m"
        )
    }
}
