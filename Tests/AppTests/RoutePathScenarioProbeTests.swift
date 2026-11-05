import CoreGraphics
@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

/// **Every shape of trip, from photographs to a film plan, on the shipped
/// path** — `ImportService` → `RouteMatchService` (a geography stub answering
/// the way Geoapify does) → `RecapComposer.filmComposition` → `LinearTimeline`
/// fitted into MapLibre's band → snapshot stations, checked frame by frame.
///
/// `ExportQualityMatrixTests` starts from a `RecapTrip` with its crossings
/// already decided. This starts from photographs, so what it adds is the half
/// the matrix assumes: which legs import makes, which ones routing and pace
/// call a crossing, which ones the homecoming cut removes.
///
/// Synthetic photographs at public places, none of them a trip anyone took
/// (`CLAUDE.md` §0).
@MainActor
final class RoutePathScenarioProbeTests: XCTestCase {
    typealias Scenario = RoutePathScenarios.Scenario
    typealias Geography = RoutePathScenarios.Geography
    typealias Form = RoutePathScenarios.Form

    /// Scenarios that fail on a filed issue. Each is expected to fail — strictly,
    /// so the day its issue is fixed this probe fails until the entry goes.
    static let knownDefects: [String: Int] = ["R1": 353]

    /// Holds one scenario's violations to nothing, or to its known defect.
    func assertNoViolations(_ violations: [String], name: String) {
        let code = String(name.prefix { $0 != " " })
        let assertion = { XCTAssertTrue(violations.isEmpty, "\(name):\n" + violations.joined(separator: "\n")) }
        guard let issue = Self.knownDefects[code] else { return assertion() }
        XCTExpectFailure("Known defect #\(issue): remove \(code) from knownDefects when it is fixed", failingBlock: assertion)
    }

    // MARK: - The probe

    func testEveryScenarioPlansAFilmThatExports() async throws {
        let full = try AppConfig.loadOrDie()
        for scenario in RoutePathScenarios.all {
            assertNoViolations(try await probe(scenario, full: full), name: scenario.name)
        }
    }

    private func probe(_ scenario: Scenario, full: TrackingConfig) async throws -> [String] {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: full)
        let tripId: String
        do {
            tripId = try await service.importTrip(title: nil, photos: scenario.photos)
        } catch {
            print("KAMOME_PROBE \(scenario.name) · import refused: \(error)")
            return []
        }
        return try await filmViolations(
            repository: repository, tripId: tripId, name: scenario.name, form: scenario.form,
            routing: scenario.routing, full: full
        )
    }

    func filmViolations(
        repository: TripRepository, tripId: String, name: String, form: Form, routing: Geography, full: TrackingConfig
    ) async throws -> [String] {
        let scenario = (name: name, form: form)
        let (detail, buttonBeforeRouting) = try await routed(
            repository: repository, tripId: tripId, name: name, routing: routing, full: full
        )
        let composition = RecapComposer.filmComposition(
            detail: detail, config: full, photosEnabled: true, length: .standard
        )
        let plan = composition.flatMap { Self.exportPlan($0.trip, config: full.export) }
        let button = Self.buttonViolations(
            name: scenario.name, beforeRouting: buttonBeforeRouting,
            afterRouting: RecapComposer.filmGoesSomewhere(detail: detail, config: full), hasPlan: plan != nil
        )
        guard button.offered else { return button.violations }
        guard let composition else {
            return ["the trip could not be composed — the export fails with no film"]
        }
        let trip = composition.trip
        let sheetS = RecapComposer.measuredFilmS(trip: trip, config: full.export)

        let config = full.export
        guard let (line, band) = plan else {
            return ["no film plan — the export fails (\(trip.legs.count) legs, \(trip.stops.count) stops)"]
        }
        let legs = trip.legs.map {
            "\($0.mode.rawValue)/\($0.provenance)\($0.isCrossing ? "/CROSSING" : "")/\($0.coordinates.count)v"
        }
        print(String(
            format: "KAMOME_PROBE %@ · type %@ · opens on flight %@ · %.1f s (sheet %.1f s) · %d film stops"
                + " · dropped %d legs %d stops · legs [%@]",
            scenario.name, "\(line.filmType)", line.opensOnTheFlight ? "yes" : "no", line.durationS, sheetS ?? -1,
            trip.stops.count, composition.droppedSegments, composition.droppedStops, legs.joined(separator: ", ")
        ))

        var violations = audit(line, trip: trip, config: config, band: band)
        switch scenario.form {
        case .local where line.opensOnTheFlight: violations.append("a local trip opens on a flight")
        case .departure where !line.filmType.hasDestinationAbroad:
            violations.append("expected a journey abroad, classified \(line.filmType)")
        default: break
        }
        if let sheetS, abs(sheetS - line.durationS) > 0.5 {
            violations.append(String(format: "the sheet says %.1f s, the export plans %.1f s", sheetS, line.durationS))
        }
        return violations
    }

    /// Routes the trip as the export does, first reading what the film button
    /// says of it: Trip Detail may read the trip before routing has answered.
    private func routed(
        repository: TripRepository, tripId: String, name: String, routing: Geography, full: TrackingConfig
    ) async throws -> (detail: TripRepository.TripDetail, buttonBeforeRouting: Bool) {
        let unrouted = try XCTUnwrap(repository.detail(tripId: tripId))
        let buttonBeforeRouting = RecapComposer.filmGoesSomewhere(detail: unrouted, config: full)
        let report = await RouteMatchService(
            repository: repository, matching: full.matching.withBaseURL("https://probe.invalid"),
            reconstructor: routing
        ).matchTrip(tripId: tripId)
        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        let verdicts = detail.segments.map { item -> String in
            let verdict = item.segment.routeVerdict.map { "\($0)" } ?? "nil"
            return "\(item.segment.mode)/\(item.points.count)pt/\(verdict)"
        }
        print("KAMOME_PROBE \(name) · \(detail.stops.count) stops"
            + " · segments [\(verdicts.joined(separator: ", "))]"
            + " · reconstructed \(report.reconstructed) beyond \(report.beyondDriving) unreachable \(report.unreachable)")
        return (detail, buttonBeforeRouting)
    }

    /// **The film button and the film agree** (#350, ADR
    /// 2026-11-04-a-trip-of-one-place-is-refused-before-the-film-button). A trip
    /// with no film plan is refused before the button, which is not a
    /// violation; a refused trip that *has* a plan is one, and so is a button
    /// that changes its mind once routing answers. `offered` is whether the
    /// button can be pressed, which is when the film itself is audited.
    static func buttonViolations(
        name: String, beforeRouting: Bool, afterRouting: Bool, hasPlan: Bool
    ) -> (offered: Bool, violations: [String]) {
        var violations: [String] = []
        if beforeRouting != afterRouting {
            violations.append("the film button changes its mind once routing answers"
                + " (before \(beforeRouting), after \(afterRouting))")
        }
        guard !afterRouting else { return (true, violations) }
        if hasPlan {
            violations.append("the film button refuses a trip that has a film plan (one place, it says)")
        } else {
            print("KAMOME_PROBE \(name) · one place: refused before the film button")
        }
        return (false, violations)
    }

    func testRecordedTripsWithAFlight() async throws {
        let full = try AppConfig.loadOrDie()
        for (name, samples) in [
            ("R1 recorded, the phone dark in the air", RoutePathScenarios.recordedFlight(airborneGPS: false)),
            ("R2 recorded, GPS on in the air", RoutePathScenarios.recordedFlight(airborneGPS: true))
        ] {
            let engine = TrackingEngine(config: full, vehicle: .car)
            engine.start(at: samples[0].ts)
            for sample in samples { engine.process(sample) }
            engine.finish(at: samples[samples.count - 1].ts)
            let stops = (engine.stops + StopDeriver.derive(
                segments: engine.segments, engineStops: engine.stops, config: full
            )).sorted { $0.arrivedAt < $1.arrivedAt }
            let stats = TripStats.compute(segments: engine.segments, stops: stops, config: full)
            let repository = TripRepository(database: try AppDatabase.inMemory())
            let tripId = try repository.saveCompletedTrip(
                title: TripTitle.unnamed, startedAt: samples[0].ts, endedAt: samples[samples.count - 1].ts,
                segments: engine.segments.map(TripRepository.NewSegment.init(recorded:)),
                stops: stops.map {
                    TripRepository.NewStop(lat: $0.lat, lon: $0.lon, arrivedAt: $0.arrivedAt,
                                           departedAt: $0.departedAt, kind: $0.kind.rawValue)
                }
            )
            if let json = stats.jsonString() { try repository.updateTripStats(tripId: tripId, statsJson: json) }
            print("KAMOME_PROBE \(name) · recorded \(engine.segments.map { "\($0.mode.rawValue)/\($0.points.count)" }) · "
                + "\(stops.count) stops · stats \(Int(stats.distanceM / 1000)) km")
            assertNoViolations(try await filmViolations(
                repository: repository, tripId: tripId, name: name, form: .any, routing: Geography(), full: full
            ), name: name)
        }
    }

    /// The plan, the way `RecapExportJob.plan` makes it on the MapLibre path.
    static func exportPlan(_ trip: RecapTrip, config: TrackingConfig.Export) -> (LinearTimeline, MercatorBand)? {
        let tripBox = GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) })
        let establishing = tripBox.flatMap { RecapMapRegionResolver.resolve(covering: $0) }.map {
            RecapBounds(minLat: $0.bounds.minLat, minLon: $0.bounds.minLon, maxLat: $0.bounds.maxLat, maxLon: $0.bounds.maxLon)
        }
        let band = MercatorBand(
            maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        guard let line = LinearTimeline(
            trip: trip, config: config, establishing: establishing, substrateMaxLongitudeDeg: nil
        )?.fitted(into: band) else { return nil }
        return (line, band)
    }
}
