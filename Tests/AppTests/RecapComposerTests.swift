@testable import Kamome
import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import KamomeTripComposer
import XCTest

/// S5 content mapping: trip records → recap cards. Copy is localized, so
/// assertions check structure (numbers, presence, fallbacks), not wording.
final class RecapComposerTests: XCTestCase {
    private let tripStart = 1_752_600_000.0

    private func trip(daysLong: Double = 1) -> TripRecord {
        TripRecord(
            id: "trip-1",
            title: "Perth Loop",
            startedAt: tripStart,
            endedAt: tripStart + daysLong * 86_400,
            status: "completed",
            statsJson: #"{"distance_m": 1203000, "drive_s": 11520, "walk_s": 3600, "stop_count": 2, "top_speed_kmh": 96}"#
        )
    }

    private func segment(
        id: String = "seg-1",
        mode: String = "drive",
        source: String? = nil,
        matchedPolyline: String? = nil,
        points: [(Double, Double)]
    ) -> (segment: SegmentRecord, points: [TrackpointRecord]) {
        let record = SegmentRecord(
            id: id, tripId: "trip-1", mode: mode, startedAt: tripStart, endedAt: tripStart + 3600,
            matchedPolyline: matchedPolyline, source: source
        )
        let trackpoints = points.enumerated().map { index, point in
            TrackpointRecord(segmentId: id, ts: tripStart + Double(index), lat: point.0, lon: point.1)
        }
        return (record, trackpoints)
    }

    private func stop(
        id: String = "stop-1",
        name: String? = "紫雲巖",
        arrivedOffset: Double = 600,
        duration: Double? = 1260,
        kind: String? = "dwell"
    ) -> StopRecord {
        StopRecord(
            id: id,
            tripId: "trip-1",
            lat: -32.0,
            lon: 115.75,
            arrivedAt: tripStart + arrivedOffset,
            departedAt: duration.map { tripStart + arrivedOffset + $0 },
            name: name,
            note: nil,
            kind: kind
        )
    }

    func testContentMapsRouteStopsAndCards() throws {
        let stops = [stop(), stop(id: "stop-2", name: nil, arrivedOffset: 90_000)]
        // Middle point well off the endpoints' chord so ε=15 m keeps it.
        let legs = RecapComposer.legs(
            from: [segment(points: [(-32.0, 115.75), (-32.1, 115.90), (-32.2, 115.77)])],
            epsilonM: 15, matchedEpsilonM: 5
        )
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: trip(daysLong: 2),
            legs: legs,
            stops: stops,
            stats: TripStats.from(jsonString: trip().statsJson),
            photosByStop: [:]
        ))

        XCTAssertEqual(recap.route.count, 3)
        XCTAssertEqual(recap.stops.count, 2)
        XCTAssertEqual(recap.stops[0].name, "紫雲巖")
        XCTAssertFalse(recap.stops[1].name.isEmpty, "unnamed stop must get the localized fallback")
        XCTAssertEqual(recap.title, "Perth Loop")
        XCTAssertTrue(recap.subtitle.contains("1203"), "subtitle carries distance, got: \(recap.subtitle)")
        // **Three figures, not a sentence** (Chiu 2026-09-05): the card sets a row
        // of KM / DAYS / STOPS, so what the composer produces is (value, label)
        // pairs and the renderer never splits a string.
        XCTAssertEqual(recap.endCardFigures.count, 3)
        let byLabel = Dictionary(
            uniqueKeysWithValues: recap.endCardFigures.map { ($0.label, $0.value) }
        )
        XCTAssertEqual(byLabel["STOPS"], "2", "the film's stop count")
        // `daysLong: 2` is two elapsed 24-hour blocks, which is Day 3 on the HUD's
        // own counter — the card and the chip must agree, so it is 3 here too.
        XCTAssertEqual(RecapComposer.dayCount(trip: trip(daysLong: 2)), 3)
        XCTAssertEqual(byLabel["DAYS"], "3", "the trip's day count")

        // 🔴 **The card measures the route the film draws, not `TripStats`.** The
        // subtitle above still carries the recorded 1,203 km; this fixture's
        // geometry is three synthetic points, so the two are far apart here by
        // construction. The figure has to be the drawn one — an imported trip has
        // no `TripStats` at all, and the card would otherwise print nothing.
        let drawnKm = Int((RecapTrip.localRouteDistanceM(legs: legs) / 1000).rounded())
        XCTAssertEqual(byLabel["KM"], "\(drawnKm)", "drawn kilometres")
        XCTAssertNotEqual(byLabel["KM"], "1,203", "the recorded total belongs to the subtitle, not the card")
    }

    func testDegenerateRouteYieldsNoTrip() {
        XCTAssertNil(RecapComposer.trip(
            trip: trip(),
            legs: RecapComposer.legs(from: [segment(points: [(-32.0, 115.75)])], epsilonM: 15, matchedEpsilonM: 5),
            stops: [],
            stats: nil,
            photosByStop: [:]
        ))
    }

    // MARK: - Provenance (PD-1) — what the film is allowed to claim

    /// The asymmetry is the point: raw geometry on a *recorded* segment is an
    /// honest GPS trace that simply never went through matching, while raw
    /// geometry on an *imported* one is a straight line between two photos
    /// nobody watched being traveled. Only the second gets dashed.
    func testProvenanceDistinguishesRecordedReconstructedAndInferred() {
        let recordedRaw = segment(source: "gps_hifi", points: [(-32.0, 115.75), (-32.1, 115.76)])
        XCTAssertEqual(RecapComposer.provenance(for: recordedRaw.segment), .recorded)

        // NULL source is a schema-v1 row — reads as recorded, same as always.
        let legacy = segment(source: nil, points: [(-32.0, 115.75), (-32.1, 115.76)])
        XCTAssertEqual(RecapComposer.provenance(for: legacy.segment), .recorded)

        let importedRaw = segment(source: "exif", points: [(-32.0, 115.75), (-32.1, 115.76)])
        XCTAssertEqual(RecapComposer.provenance(for: importedRaw.segment), .inferred)
        XCTAssertTrue(RecapComposer.provenance(for: importedRaw.segment).isInferred)

        // Snapped geometry is a confident claim whichever way the trip arrived.
        let snapped = EncodedPolyline.encode([GeoPoint(lat: -32.0, lon: 115.75), GeoPoint(lat: -32.1, lon: 115.76)])
        let importedSnapped = segment(source: "exif", matchedPolyline: snapped, points: [(-32.0, 115.75), (-32.1, 115.76)])
        XCTAssertEqual(RecapComposer.provenance(for: importedSnapped.segment), .reconstructed)
        let recordedSnapped = segment(source: "gps_hifi", matchedPolyline: snapped, points: [(-32.0, 115.75), (-32.1, 115.76)])
        XCTAssertEqual(RecapComposer.provenance(for: recordedSnapped.segment), .reconstructed)
    }

    /// One leg per stored segment, each keeping its own mode and provenance —
    /// a mixed trip must not collapse to a single claim.
    func testLegsCarryPerSegmentModeAndProvenance() {
        let snapped = EncodedPolyline.encode([GeoPoint(lat: -32.0, lon: 115.75), GeoPoint(lat: -32.1, lon: 115.76)])
        let legs = RecapComposer.legs(
            from: [
                segment(id: "a", mode: "drive", source: "exif", matchedPolyline: snapped,
                        points: [(-32.0, 115.75), (-32.1, 115.76)]),
                segment(id: "b", mode: "walk", source: "exif",
                        points: [(-32.1, 115.76), (-32.11, 115.77)])
            ],
            epsilonM: 15, matchedEpsilonM: 5
        )
        XCTAssertEqual(legs.map(\.provenance), [.reconstructed, .inferred])
        XCTAssertEqual(legs.map(\.mode), [.drive, .walk])
    }

    /// PD-4: the MVP film's end card carries no QR, so the composer emits no
    /// payload for one. `kamome://route/<id>` resolves to nothing.
    func testTripCarriesNoShareURLForTheMVPFilm() throws {
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: trip(),
            legs: RecapComposer.legs(
                from: [segment(points: [(-32.0, 115.75), (-32.1, 115.76)])], epsilonM: 15, matchedEpsilonM: 5
            ),
            stops: [], stats: nil, photosByStop: [:]
        ))
        XCTAssertNil(recap.shareURL)
        XCTAssertFalse(recap.endCardFigures.isEmpty, "the card's figures stay — only the unresolved code goes")
    }

    /// The opening title's date range is the trip's **real** span, straight from
    /// `trip.startedAt`/`endedAt` — which for an import are the first and last
    /// photo's EXIF times. A one-day fixture reads as one date because the trip
    /// is one day, not because anything is hardcoded to look that way.
    func testTitleSubtitleShowsTheTripsRealDateRange() {
        let oneDay = RecapComposer.titleSubtitle(trip: trip(daysLong: 0), distanceM: nil)
        let nineDays = RecapComposer.titleSubtitle(trip: trip(daysLong: 9), distanceM: nil)
        XCTAssertNotEqual(oneDay, nineDays, "a nine-day trip must not print like a one-day one")
        // A multi-day trip prints a range; a same-day trip collapses to one date.
        XCTAssertTrue(nineDays.contains("–") || nineDays.contains("-") || nineDays.contains("—"),
                      "expected a range, got: \(nineDays)")
        XCTAssertFalse(oneDay.contains("–"), "expected a single date, got: \(oneDay)")
    }

    /// **Every kilometre a viewer reads is the local journey** (Chiu 2026-09-02):
    /// the HUD odometer, the title card's subtitle, and the end card's stats.
    ///
    /// Two of the three are here because they come from the same `stats.distanceM`
    /// and were the ones left at 9,024 km when only the odometer was corrected.
    /// The flight is not deleted — it appears once, on the Journey Card, labelled
    /// as the flight (`RecapJourneyCardTests`).
    func testTheCardsCountTheLocalJourneyAndNotTheFlight() throws {
        // One short drive, then a leg routing answered "no road" for: ~1,100 km of
        // it, against a trip whose recorded distance is 1,203 km.
        let drive = segment(points: [(-32.0, 115.75), (-32.1, 115.90)])
        let flight = segment(
            id: "seg-2", source: "exif", points: [(-32.1, 115.90), (-22.0, 115.90)]
        )
        let crossing = (
            segment: SegmentRecord(
                id: "seg-2", tripId: "trip-1", mode: "drive", startedAt: tripStart,
                endedAt: tripStart + 3600, matchedPolyline: nil, source: "exif",
                routability: SegmentRoutability.noRoad.rawValue
            ),
            points: flight.points
        )
        let legs = RecapComposer.legs(from: [drive, crossing], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertEqual(legs.filter(\.isCrossing).count, 1, "the fixture must contain one crossing")

        let stats = try XCTUnwrap(TripStats.from(jsonString: trip().statsJson))
        let localM = try XCTUnwrap(RecapComposer.localDistanceM(stats: stats, legs: legs))
        XCTAssertLessThan(localM, stats.distanceM, "the flight must come off the reported distance")
        XCTAssertGreaterThan(localM, 0, "and it must never take the figure negative")

        // Both card surfaces print a local figure and neither prints the whole
        // trip's. Structure, not wording — the copy is localized.
        //
        // 🔴 **They no longer print the same local figure, deliberately** (ADR
        // 2026-09-05). The subtitle carries the *recorded* total with the flight
        // subtracted; the closing card measures the *route the film draws*, which
        // is the odometer's own axis and the only figure an imported trip has at
        // all. What both still owe is that the flight is not in them.
        let subtitle = RecapComposer.titleSubtitle(trip: trip(), distanceM: localM)
        let drawnM = RecapTrip.localRouteDistanceM(legs: legs)
        let km = try XCTUnwrap(
            RecapComposer.endCardFigures(trip: trip(), distanceM: drawnM, stopCount: 2).first
        )
        let whole = "\(Int((stats.distanceM / 1000).rounded()))"
        let local = "\(Int((localM / 1000).rounded()))"
        XCTAssertTrue(subtitle.contains(local), "the title card prints the local journey")
        XCTAssertFalse(subtitle.contains(whole), "and never the whole trip: \(subtitle)")
        XCTAssertEqual(km.label, "KM", "the distance is the row's first figure")
        XCTAssertEqual(
            km.value, "\(Int((drawnM / 1000).rounded()))", "the end card prints the route it drew"
        )
        XCTAssertNotEqual(km.value, whole, "and never the whole trip")
        // The flight is excluded from that axis **by construction**, which is what
        // stops the closing card ever reading 9,024 km again.
        XCTAssertLessThan(
            drawnM, RecapTrip.localRouteDistanceM(legs: legs.map(Self.notACrossing)),
            "the crossing must not be in the card's figure"
        )
    }

    /// The same leg, declared routable — so `localRouteDistanceM` counts it. Used
    /// only to measure how much the crossing contributes.
    private static func notACrossing(_ leg: RecapTrip.Leg) -> RecapTrip.Leg {
        RecapTrip.Leg(coordinates: leg.coordinates, mode: leg.mode, provenance: leg.provenance)
    }

    /// **A local trip's kilometres are unchanged**, which is the type-1 control's
    /// half of the same rule: with no crossing there is nothing to subtract, so
    /// the figure is exactly `stats.distanceM` and no film moved.
    func testALocalTripsDistanceIsUntouched() throws {
        let legs = RecapComposer.legs(
            from: [segment(points: [(-32.0, 115.75), (-32.1, 115.90)])], epsilonM: 15, matchedEpsilonM: 5
        )
        let stats = try XCTUnwrap(TripStats.from(jsonString: trip().statsJson))
        XCTAssertEqual(RecapComposer.localDistanceM(stats: stats, legs: legs), stats.distanceM)
    }

    func testDayLabelsUseS3DayMath() {
        // Same-day arrival → day 1; 25 h in → day 2.
        XCTAssertTrue(RecapComposer.dayLabel(for: tripStart + 600, tripStartedAt: tripStart).contains("1"))
        XCTAssertTrue(RecapComposer.dayLabel(for: tripStart + 90_000, tripStartedAt: tripStart).contains("2"))
    }

    func testWalkVisitGetsDetailLineOthersDoNot() throws {
        // 21 min walk visit → detail with the minute count.
        let visit = stop(duration: 1260, kind: "walk_visit")
        let detail = try XCTUnwrap(RecapComposer.walkDetail(for: visit))
        XCTAssertTrue(detail.contains("21"))

        // Dwell, legacy "auto", missing kind, open-ended visit: no line.
        XCTAssertNil(RecapComposer.walkDetail(for: stop(kind: "dwell")))
        XCTAssertNil(RecapComposer.walkDetail(for: stop(kind: "auto")))
        XCTAssertNil(RecapComposer.walkDetail(for: stop(kind: nil)))
        XCTAssertNil(RecapComposer.walkDetail(for: stop(duration: nil, kind: "walk_visit")))
    }

    func testStopPhotosComeFromProvidedRefs() throws {
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: trip(),
            legs: RecapComposer.legs(
                from: [segment(points: [(-32.0, 115.75), (-32.1, 115.76)])], epsilonM: 15, matchedEpsilonM: 5
            ),
            stops: [stop()],
            stats: nil,
            photosByStop: ["stop-1": [.asset("asset-a"), .asset("asset-b")]]
        ))
        // Refs pass through untouched — data layer points, never loads.
        XCTAssertEqual(recap.stops[0].photos, [.asset("asset-a"), .asset("asset-b")])
    }

    func testRouteSimplifiesDenseCollinearRuns() {
        // 500 straight-line points → ε=15 m keeps only the endpoints, so an
        // 8-day trip's stroke cost stays inside the §4.5 render budget.
        let dense = (0..<500).map { (-32.0 + Double($0) * 0.0001, 115.75) }
        let route = RecapComposer.route(from: [segment(points: dense)], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertGreaterThanOrEqual(route.count, 2)
        XCTAssertLessThan(route.count, 10, "collinear run must collapse")
    }

    func testMatchedSegmentUsesSnappedGeometryOverRawPoints() {
        // Raw trace cuts the corner; the stored matched polyline follows it.
        let snapped = [
            GeoPoint(lat: -32.00, lon: 115.75),
            GeoPoint(lat: -32.05, lon: 115.85),
            GeoPoint(lat: -32.20, lon: 115.77)
        ]
        var matched = segment(points: [(-32.0, 115.75), (-32.2, 115.77)])
        matched.segment.matchedPolyline = EncodedPolyline.encode(snapped)

        let route = RecapComposer.route(from: [matched], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertEqual(route.count, 3, "snapped geometry must replace the raw 2-point chord")
        XCTAssertEqual(route[1].lat, -32.05, accuracy: 0.0001)
        XCTAssertEqual(route[1].lon, 115.85, accuracy: 0.0001)
    }

    func testDegenerateMatchedPolylineFallsBackToRawPoints() {
        // A 1-point (or corrupt) stored polyline must never erase the route.
        var matched = segment(points: [(-32.0, 115.75), (-32.1, 115.90), (-32.2, 115.77)])
        matched.segment.matchedPolyline = EncodedPolyline.encode([GeoPoint(lat: -32.0, lon: 115.75)])

        let route = RecapComposer.route(from: [matched], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertEqual(route.count, 3, "raw points are the fallback")
    }

    func testShareURLEncodesTripId() {
        XCTAssertEqual(RecapComposer.shareURLString(tripId: "abc-123"), "kamome://route/abc-123")
    }
}
