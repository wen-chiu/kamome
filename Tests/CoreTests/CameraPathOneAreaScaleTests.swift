import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **A film framed in one area is framed by its own journey, never by the
/// country under its title card** (#187).
///
/// The opening holds one beat under the title — the country, when the country
/// adds context (Chiu 2026-09-29) — and zooms into the journey. A film with
/// several areas takes its scale from them. A film with one area still divides
/// "what the opening establishes" by `target_zoom_ratio`, and since the regional
/// beat left the screen that was the country: 271 km of road in Western
/// Australia was framed 1,621 km wide, a walk round one city the same. These pin
/// the journey's own frame as what the body divides, on the shipped tunables.
final class CameraPathOneAreaScaleTests: XCTestCase {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")

    private func shipped() throws -> TrackingConfig.Export {
        try TrackingConfigLoader.load(contentsOf: Self.configURL).export
    }

    /// One trip in a country far wider than the trip. Public places only.
    private struct Trip {
        let route: [CameraPath.Point]
        let stops: [CameraPath.Point]
    }

    /// A coast road with four evenly spaced stops: Perth to Margaret River,
    /// `DemoSeeder`'s route. Every stretch asks for much the same span, so the
    /// film is one area from the start.
    private var coastRoad: Trip {
        let route = [
            (-31.9530, 115.8570), (-32.1200, 115.8200), (-32.3200, 115.7700),
            (-32.5290, 115.7220), (-32.8000, 115.7000), (-33.0500, 115.6800),
            (-33.3270, 115.6410), (-33.5000, 115.5000), (-33.6440, 115.3450),
            (-33.8000, 115.2000), (-33.9550, 115.0750)
        ].map { CameraPath.Point(lat: $0.0, lon: $0.1) }
        return Trip(route: route, stops: [3, 6, 8, 10].map { route[$0] })
    }

    /// A walk round one city, four stops inside two kilometres: Sydney, from
    /// the Opera House south. Every stretch asks for `camera_span_m`.
    private var cityWalk: Trip {
        let route = [
            (-33.8568, 151.2153), (-33.8600, 151.2090), (-33.8700, 151.2070), (-33.8830, 151.2000)
        ].map { CameraPath.Point(lat: $0.0, lon: $0.1) }
        return Trip(route: route, stops: route)
    }

    /// The camera as `LinearTimeline` builds it for the shipped app: no
    /// installed region, and the opening and the closing chrome the duration
    /// plan reserves. `opening: false` is the same film with no title card.
    private func camera(_ trip: Trip, opening: Bool, config: TrackingConfig.Export) throws -> CameraPath {
        try XCTUnwrap(CameraPath(
            route: trip.route, stops: trip.stops, config: config, totalDurationS: config.totalDurationMinS,
            openingS: opening ? config.titleCardS + config.openingRegionalS + config.zoomTransitionS : 0,
            journeyEndsBeforeS: config.endCardS + config.endRouteHoldS
        ))
    }

    /// The frame that holds the whole journey with `wide_span_padding` round it
    /// — what the body divides, and the widest it may ever be.
    private func journeyFrameM(_ trip: Trip, config: TrackingConfig.Export) -> Double {
        CameraPath.frame(for: CameraPath.bounds(of: trip.route), config: config, padding: config.wideSpanPadding).spanM
    }

    /// Both fixtures have to be what this file is about: one area, under a
    /// title card that shows far more than the journey. If either stops being
    /// true the tests below pass without testing anything.
    func testTheFixturesAreOneAreaFilmsUnderACountryCard() throws {
        let config = try shipped()
        for (name, trip) in [("coast road", coastRoad), ("city walk", cityWalk)] {
            let film = try camera(trip, opening: true, config: config)
            XCTAssertEqual(film.areaSpansM.count, 1, "\(name) is no longer framed in one area")
            XCTAssertGreaterThan(
                film.cameraFrame(atTime: 0).spanM, 10 * journeyFrameM(trip, config: config),
                "\(name)'s title card no longer shows a country far wider than the journey"
            )
        }
    }

    /// **The title card does not change the scale of the film under it.** The
    /// same journey with and without an opening is framed the same.
    func testTheTitleCardDoesNotChangeTheBodysScale() throws {
        let config = try shipped()
        for (name, trip) in [("coast road", coastRoad), ("city walk", cityWalk)] {
            let with = try camera(trip, opening: true, config: config).bodySpanM
            let without = try camera(trip, opening: false, config: config).bodySpanM
            XCTAssertEqual(
                with, without, accuracy: 1,
                "\(name): \(Int(without)) m wide with no title card, \(Int(with)) m wide under one"
            )
        }
    }

    /// **The body is never wider than the frame that holds the journey** —
    /// `RecapDurationPlan.bodySpanM`'s own ceiling, measured against the
    /// journey rather than against whatever the card shows.
    func testTheBodyIsNeverWiderThanTheJourneysOwnFrame() throws {
        let config = try shipped()
        for (name, trip) in [("coast road", coastRoad), ("city walk", cityWalk)] {
            let bodyM = try camera(trip, opening: true, config: config).bodySpanM
            XCTAssertLessThanOrEqual(
                bodyM, journeyFrameM(trip, config: config) + 1,
                "\(name) is framed \(Int(bodyM)) m wide; the whole journey fits in \(Int(journeyFrameM(trip, config: config))) m"
            )
        }
    }

    /// **A city walk is framed at city scale**: every stretch asks for
    /// `camera_span_m`, and a country under the title does not widen it.
    func testACityWalkIsFramedAtCityScale() throws {
        let config = try shipped()
        XCTAssertEqual(try camera(cityWalk, opening: true, config: config).bodySpanM, config.cameraSpanM, accuracy: 1)
    }
}
