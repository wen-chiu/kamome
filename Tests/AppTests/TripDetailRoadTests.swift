@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import KamomeTripComposer
import MapKit
import XCTest

/// **Trip Detail draws the road it names** (Chiu 2026-10-26, #195; ADR
/// 2026-10-26-the-in-app-map-draws-the-road-it-names). The map drew every leg
/// from its two photographs while the diary called the leg 「已對齊道路」, and
/// framed more than the trip (#295 item 5).
@MainActor
final class TripDetailRoadTests: XCTestCase {
    /// Invented places. Three stops due north of each other; the first leg's
    /// road swings ~5 km east of the straight line between its stops, the
    /// second leg was refused a road (`implausibleRoute`, nothing stored).
    private struct Fixture {
        let model: TripDetailModel
        let matched: SegmentRecord
        let refused: SegmentRecord
        let road: [Simplifier.Point]
        let detail: TripRepository.TripDetail
    }

    private func fixture() async throws -> Fixture {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let start = 1_787_382_000.0
        let ends = [(lat: 10.0, lon: 20.0), (lat: 10.2, lon: 20.0), (lat: 10.4, lon: 20.0)]
        let times = [(arrive: start, depart: start + 1_800), (arrive: start + 7_200, depart: start + 9_000),
                     (arrive: start + 14_400, depart: start + 16_200)]
        let segments = (0..<2).map { index in
            TripRepository.NewSegment(
                mode: "drive", startedAt: times[index].depart, endedAt: times[index + 1].arrive,
                points: [
                    TripRepository.NewTrackpoint(ts: times[index].depart, lat: ends[index].lat, lon: ends[index].lon),
                    TripRepository.NewTrackpoint(ts: times[index + 1].arrive, lat: ends[index + 1].lat, lon: ends[index + 1].lon)
                ],
                source: SegmentSource.exif.rawValue
            )
        }
        let stops = zip(ends, times).map { end, time in
            TripRepository.NewStopWithPhotos(
                stop: TripRepository.NewStop(lat: end.lat, lon: end.lon, arrivedAt: time.arrive, departedAt: time.depart),
                photos: []
            )
        }
        let tripId = try repository.saveImportedTrip(TripRepository.ImportedTrip(
            title: "road", startedAt: start, endedAt: start + 16_200, source: TripSource.importedPhotos.rawValue,
            segments: segments, stopsWithPhotos: stops, routeAttachedPhotos: []
        ))
        let stored = try XCTUnwrap(repository.detail(tripId: tripId)).segments.map(\.segment)
            .sorted { $0.startedAt < $1.startedAt }
        let road = (0...40).map { step in
            GeoPoint(lat: 10.0 + 0.005 * Double(step), lon: 20.0 + 0.05 * sin(Double.pi * Double(step) / 40))
        }
        try repository.setMatchedPolyline(segmentId: stored[0].id, encodedPolyline: EncodedPolyline.encode(road))
        try repository.setRoutability(segmentId: stored[0].id, .road)
        try repository.setRoutability(segmentId: stored[1].id, .implausibleRoute)

        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        await model.refresh()
        let detail = try XCTUnwrap(model.detail)
        let byId = Dictionary(uniqueKeysWithValues: detail.segments.map { ($0.segment.id, $0.segment) })
        // The road as stored: the polyline's own precision, not the doubles above.
        let decoded = EncodedPolyline.decode(EncodedPolyline.encode(road)).map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }
        return Fixture(
            model: model, matched: try XCTUnwrap(byId[stored[0].id]), refused: try XCTUnwrap(byId[stored[1].id]),
            road: decoded, detail: detail
        )
    }

    /// **The test #195 owed.** A leg with a stored road is drawn along that
    /// road, thinned as the film thins it; a leg without one keeps its two
    /// photographs. And each is named for what is drawn: only the road is
    /// 「已對齊道路」 in the diary.
    func testAMatchedLegIsDrawnAlongItsRoadAndNamedForIt() async throws {
        let fixture = try await fixture()
        let config = fixture.model.config

        let drawn = fixture.model.displayPolyline(for: fixture.matched)
        XCTAssertEqual(drawn, Simplifier.douglasPeucker(fixture.road, epsilonM: config.matching.displayEpsilonM),
                       "the matched leg is the road, at the film's road ε")
        XCTAssertGreaterThan(drawn.count, 2, "two points would be the straight line between the stops")
        XCTAssertGreaterThan(drawn.map(\.lon).max() ?? 0, 20.04, "the line follows the road's swing east")

        XCTAssertEqual(fixture.model.displayPolyline(for: fixture.refused),
                       [Simplifier.Point(lat: 10.2, lon: 20.0), Simplifier.Point(lat: 10.4, lon: 20.0)],
                       "a leg with no road keeps today's line: its own points")

        XCTAssertEqual(RecapComposer.provenance(for: fixture.matched), .reconstructed)
        XCTAssertEqual(RecapComposer.provenance(for: fixture.refused), .inferred)
        let legs = JourneyItinerary(detail: fixture.detail).days.flatMap { $0.entries.compactMap(\.leg) }
        XCTAssertEqual(legs.map(\.provenance), [.reconstructed, .inferred],
                       "the diary names the drawn road 「已對齊道路」 and nothing else")
    }

    /// **The map frames the trip itself** (#295 item 5): everything it draws —
    /// the road's swing east of the stops included — and no more than
    /// `trip_map.frame_padding` around it.
    func testTheMapFramesWhatItDrawsAndNoMore() async throws {
        let fixture = try await fixture()
        let tripMap = fixture.model.config.tripMap
        let frame = try XCTUnwrap(fixture.model.mapFrame)
        let drawn = fixture.model.visibleSegments.flatMap { fixture.model.displayPolyline(for: $0.segment) }
        let lats = drawn.map(\.lat), lons = drawn.map(\.lon)
        let latExtent = (lats.max() ?? 0) - (lats.min() ?? 0)
        let lonExtent = (lons.max() ?? 0) - (lons.min() ?? 0)

        XCTAssertEqual(frame.centerLat, 10.2, accuracy: 1e-9)
        XCTAssertEqual(frame.centerLon, ((lons.max() ?? 0) + (lons.min() ?? 0)) / 2, accuracy: 1e-9,
                       "centred on what is drawn, the road's swing included")
        XCTAssertEqual(frame.latSpan, latExtent * tripMap.framePadding, accuracy: 1e-9)
        XCTAssertEqual(frame.lonSpan, lonExtent * tripMap.framePadding, accuracy: 1e-9)
        XCTAssertGreaterThan(lonExtent, 0.04, "the stops alone are one meridian; the road is what is wide")
    }

    /// A trip astride 180° is framed across it, not round the planet.
    func testATripAstrideTheAntimeridianIsFramedAcrossIt() throws {
        let tripMap = AppConfig.loadOrDie().tripMap
        let frame = try XCTUnwrap(TripMapFrame(
            points: [Simplifier.Point(lat: 0.0, lon: 179.95), Simplifier.Point(lat: 0.1, lon: -179.95)], config: tripMap
        ))
        XCTAssertEqual(frame.lonSpan, 0.1 * tripMap.framePadding, accuracy: 1e-6)
        XCTAssertEqual(abs(frame.centerLon), 180, accuracy: 1e-6)
    }

    /// One place is framed at `frame_min_span_m`, not at a pin's width; and
    /// with nothing drawn there is no frame, so the map keeps MapKit's own.
    func testOnePlaceIsFramedAtTheNarrowestSpanAndNothingIsNotFramed() throws {
        let tripMap = AppConfig.loadOrDie().tripMap
        let frame = try XCTUnwrap(TripMapFrame(points: [Simplifier.Point(lat: 10.0, lon: 20.0)], config: tripMap))
        let narrowest = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10.0, longitude: 20.0),
            latitudinalMeters: tripMap.frameMinSpanM, longitudinalMeters: tripMap.frameMinSpanM
        ).span
        XCTAssertEqual(frame.latSpan, narrowest.latitudeDelta, accuracy: 1e-12)
        XCTAssertEqual(frame.lonSpan, narrowest.longitudeDelta, accuracy: 1e-12)
        XCTAssertNil(TripMapFrame(points: [], config: tripMap))
    }
}
