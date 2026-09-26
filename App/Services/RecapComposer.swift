import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer

/// Maps one trip's records into §4.5 recap inputs (S5). Pure value mapping —
/// photo CGImages arrive pre-loaded (RecapModel owns PhotoKit), and all copy
/// is formatted here so localization never enters KamomeExportEngine.
enum RecapComposer {
    /// Display-grade recap geometry, one `RecapTrip.Leg` per stored segment.
    /// Segments matched to the road network (§4.4, `segment.matched_polyline`)
    /// contribute their snapped geometry at the tighter matched ε — the replay
    /// must follow real roads, never straight lines between GPS points (§4.5
    /// quality bar). Unmatched segments fall back to raw points at the same ε as
    /// S3. Either way the compositor strokes the traveled path every frame, so
    /// everything is Douglas-Peucker-bounded to protect the §4.5 render budget.
    ///
    /// Each leg also carries **why its geometry looks the way it does**, which
    /// the film draws (PD-1) — see `provenance(for:)`.
    static func legs(
        from segments: [(segment: SegmentRecord, points: [TrackpointRecord])],
        epsilonM: Double,
        matchedEpsilonM: Double
    ) -> [RecapTrip.Leg] {
        segments.compactMap { item -> RecapTrip.Leg? in
            let source: (points: [Simplifier.Point], epsilonM: Double)
            if let encoded = item.segment.matchedPolyline,
               case let decoded = EncodedPolyline.decode(encoded),
               decoded.count >= 2 {
                source = (decoded.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, matchedEpsilonM)
            } else {
                source = (item.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, epsilonM)
            }
            let coordinates = Simplifier.douglasPeucker(source.points, epsilonM: source.epsilonM)
                .map { RecapCoordinate(lat: $0.lat, lon: $0.lon) }
            guard coordinates.count >= 2 else { return nil }
            return RecapTrip.Leg(
                coordinates: coordinates,
                mode: TransportMode(rawValue: item.segment.mode) ?? .unknown,
                provenance: provenance(for: item.segment),
                isCrossing: isCrossing(item.segment)
            )
        }
    }

    /// Derives a segment's provenance from what the row actually says (PD-1).
    /// No confidence column is needed: snapped geometry either exists or it
    /// doesn't, and the segment knows whether it was recorded or reconstructed
    /// from photos.
    ///
    /// Note the asymmetry, and that it is deliberate: raw geometry on a
    /// *recorded* segment is honest — it is a real GPS trace that simply never
    /// went through matching — while raw geometry on an *imported* segment is a
    /// straight line between two photos that nobody watched being traveled. Only
    /// the second is inferred, and only the second gets dashed.
    static func provenance(for segment: SegmentRecord) -> RouteProvenance {
        if segment.matchedPolyline != nil { return .reconstructed }
        switch segment.segmentSource {
        case .gpsHifi, .gpsPassive: return .recorded
        case .exif, .timeline, .mergeGap: return .inferred
        }
    }

    /// Whether this segment is a **crossing**: routing answered that no road
    /// joins its ends (`Docs/camera-arcs.md` §0), **or** the leg was covered too
    /// fast to have been driven (`beyondDriving`, ADR 2026-09-24 (f), which
    /// reopened "one verdict and nothing else").
    ///
    /// Stored verdicts only — the pace is judged once, in `RouteMatchService`,
    /// never here. NULL (nobody asked, routing disabled, the provider never
    /// answered) is still `false`, because the honest reading of "we do not
    /// know" is "do not fly a sprite over it".
    static func isCrossing(_ segment: SegmentRecord) -> Bool {
        switch segment.routeVerdict {
        case .noRoad?, .beyondDriving?: return true
        case .road?, .implausibleRoute?, .offRoadNetwork?, nil: return false
        }
    }

    /// Whether routing answered — with any of its three verdicts — for **every**
    /// segment of this trip (`RecapTrip.everyLegRoutabilityEstablished`).
    ///
    /// The film type needs the distinction `isCrossing` deliberately throws
    /// away. That Bool reads NULL as "not a crossing", which is right for *the
    /// camera* — never fly a sprite over a leg nobody asked about — and wrong for
    /// *the type*, where a NULL leg is a crossing that may simply not have been
    /// established yet. One trip, two honest readings of the same nil.
    ///
    /// An empty trip answers `false`: nothing was established because there was
    /// nothing to establish, and `RecapFilmType.unknown` is the truthful verdict
    /// on a journey with no legs.
    ///
    /// ⚠️ Counts **every** segment handed in, including any too degenerate to
    /// become a leg (`legs(from:)` drops those under two points). Deliberate: a
    /// dropped segment is still a stretch routing was meant to answer for, and
    /// counting it errs toward `unknown`, which is the safe direction.
    static func everyLegRoutabilityEstablished(
        _ segments: [(segment: SegmentRecord, points: [TrackpointRecord])]
    ) -> Bool {
        !segments.isEmpty && segments.allSatisfy { $0.segment.routeVerdict != nil }
    }

    /// The whole display polyline. Kept for callers that only need geometry
    /// (S3's map, distance math) — the film goes through `legs`.
    static func route(
        from segments: [(segment: SegmentRecord, points: [TrackpointRecord])],
        epsilonM: Double,
        matchedEpsilonM: Double
    ) -> [RecapCoordinate] {
        legs(from: segments, epsilonM: epsilonM, matchedEpsilonM: matchedEpsilonM)
            .flatMap(\.coordinates)
    }

    /// Maps one trip's records into the style-independent `RecapTrip` (S5).
    /// `photosByStop` maps stop id → the stop's deck photo *candidates*, in time
    /// order — refs, not bitmaps; the render layer resolves them. With weighting,
    /// each stop's deck is picked from these **after** allocation, at its final
    /// size (`PhotoDeckSelector.pick`); `highlightedAssets` lead and, up to
    /// `highlightMaxPhotos`, raise the size (Chiu 2026-09-24). Without weighting
    /// the candidates are shown as given. `deck` + `stopHoldS` size each stop's dwell from its
    /// photo count. Returns nil for trips the phantom guard should have kept out
    /// anyway (no route points).
    static func trip(
        trip: TripRecord,
        legs: [RecapTrip.Leg],
        stops: [StopRecord],
        stats: TripStats?,
        photosByStop: [String: [PhotoRef]],
        deck: RecapDeck = RecapDeck(),
        stopHoldS: Double = 1.5,
        rawPhotoCounts: [String: Int] = [:],
        favoriteCounts: [String: Int] = [:],
        highlightedAssets: Set<String> = [],
        pickedAssets: Set<String> = [],
        pickedCounts: [String: Int] = [:],
        analysis: PhotoAnalysisInputs? = nil,
        highlightMaxPhotos: Int = 0,
        weighting: TrackingConfig.Export? = nil,
        everyLegRoutabilityEstablished: Bool = false,
        clock: TripClock? = nil
    ) -> RecapTrip? {
        guard legs.reduce(0, { $0 + $1.coordinates.count }) >= 2 else { return nil }
        // Every day and date the film draws is local to where it happened
        // (`TripClock`); the export passes the whole trip's stops so the trip's
        // last moment, after the film's own end, is counted in its own zone.
        let clock = clock ?? TripClock(stops: stops)

        let inputs = PhotoInputs(
            byStop: photosByStop, highlighted: highlightedAssets,
            rawCounts: rawPhotoCounts, starredCounts: favoriteCounts,
            picked: pickedAssets, pickedCounts: pickedCounts, analysis: analysis
        )
        let plan = deckPlan(stops: stops, inputs: inputs, highlightMaxPhotos: highlightMaxPhotos, weighting: weighting)
        let tripStops = plan.map { stop, photos -> RecapTrip.Stop in
            RecapTrip.Stop(
                coordinate: snapped(lat: stop.lat, lon: stop.lon, to: legs),
                name: stop.name ?? String(localized: "stop_unnamed"),
                dayLabel: dayLabel(for: stop.arrivedAt, tripStartedAt: trip.startedAt, clock: clock),
                detail: walkDetail(for: stop),
                photos: photos,
                dwellS: photos.isEmpty ? stopHoldS : deck.dwellS(photoCount: photos.count),
                // "" is stored for "asked, none came back" (`StopNamer`).
                locality: stop.locality.flatMap { $0.isEmpty ? nil : $0 }
            )
        }

        // **Every kilometre the film shows a viewer is the local journey**
        // (Chiu 2026-09-02) — the flight appears once, on the boarding pass, and
        // is labelled there. The title card's subtitle takes the recorded total
        // with the flown legs subtracted; the closing card measures the journey it
        // just showed (`filmJourney`), which is the same axis the HUD odometer
        // counts. Fixing one of the three and not the others is exactly how
        // 9,024 km survived on two cards after the odometer was corrected.
        let localM = localDistanceM(stats: stats, legs: legs)
        let film = filmJourney(
            legs: legs, stops: tripStops, config: weighting,
            everyLegRoutabilityEstablished: everyLegRoutabilityEstablished
        )
        // An imported trip has no `TripStats` (`ImportService` writes none), so
        // `localM` is nil and the card would print dates only. The composer already
        // holds the journey the film will draw — before a frame exists — so it
        // falls back to measuring that, on the same axis the end card and the HUD
        // odometer use. Recorded trips are untouched: their stored total stays the
        // base (see `localDistanceM`). Zero prints nothing rather than "0 km".
        let drawnM = RecapTrip.localRouteDistanceM(legs: film.legs)
        let titleM = localM ?? (drawnM > 0 ? drawnM : nil)
        return RecapTrip(
            legs: legs,
            stops: tripStops,
            title: trip.title,
            subtitle: titleSubtitle(trip: trip, distanceM: titleM),
            endCardFigures: endCardFigures(
                trip: trip, distanceM: drawnM, stopCount: film.stops.count, clock: clock
            ),
            shareURL: nil,
            journeyDates: journeyDates(trip, clock: clock),
            everyLegRoutabilityEstablished: everyLegRoutabilityEstablished
        )
    }

    /// The stop's pin, moved onto the route the film actually draws
    /// (Chiu 2026-08-06).
    ///
    /// A stop's stored coordinate is the **centroid of the photographs taken
    /// there** — where the person stood, which is the honest record and stays in
    /// the database untouched. The route drawn is the OSRM road-snapped geometry.
    /// Those are different places by however far the layby is from the centreline,
    /// so on every reconstructed leg the pin floated beside its own trail.
    ///
    /// Display-only, and a no-op on unreconstructed legs: those are drawn from the
    /// stop anchors themselves, so the polyline already passes through the centroid
    /// and the nearest point is the centroid.
    /// **Projects onto the segments, not the vertices** (2026-08-06). Snapping to
    /// the nearest *vertex* looks right wherever the polyline is dense and wrong
    /// wherever it is sparse — and it is sparse by construction, because every leg
    /// goes through Douglas-Peucker before it is drawn. On a long straight highway
    /// the nearest vertex can be kilometres from the nearest point on the road, so
    /// the pin still floated. That is why the first fix looked correct on Variant B
    /// (12 stops, all at dense landmark geometry) and still failed on Variant A
    /// (every stop, including the ones out on simplified straights).
    static func snapped(lat: Double, lon: Double, to legs: [RecapTrip.Leg]) -> RecapCoordinate {
        var best = RecapCoordinate(lat: lat, lon: lon)
        var bestDistance = Double.greatestFiniteMagnitude
        for leg in legs {
            for (start, end) in zip(leg.coordinates, leg.coordinates.dropFirst()) {
                let candidate = projection(lat: lat, lon: lon, start: start, end: end)
                let distance = PhotoImportClusterer.haversineMeters(lat, lon, candidate.lat, candidate.lon)
                if distance < bestDistance {
                    bestDistance = distance
                    best = candidate
                }
            }
        }
        return best
    }

    /// The closest point on one segment, in a local equirectangular frame.
    ///
    /// Longitude is scaled by cos(latitude) so a degree east matches a degree
    /// north in metres; over a single simplified segment that approximation is far
    /// below the width of the road being drawn, and it keeps this to arithmetic
    /// rather than a spherical solve.
    private static func projection(
        lat: Double, lon: Double, start: RecapCoordinate, end: RecapCoordinate
    ) -> RecapCoordinate {
        let scale = cos(lat * .pi / 180)
        let startX = (start.lon - lon) * scale, startY = start.lat - lat
        let endX = (end.lon - lon) * scale, endY = end.lat - lat
        let dx = endX - startX, dy = endY - startY
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }
        // Clamped, so a stop beside the *middle* of a leg projects onto the road
        // while a stop beyond either end lands on that end rather than off the map.
        let along = min(max(-(startX * dx + startY * dy) / lengthSquared, 0), 1)
        return RecapCoordinate(lat: start.lat + (end.lat - start.lat) * along,
                               lon: start.lon + (end.lon - start.lon) * along)
    }

    /// Same day math as S3's filter chips: the local date where it happened
    /// (`TripClock`).
    static func dayLabel(for timestamp: Double, tripStartedAt: Double, clock: TripClock) -> String {
        let day = clock.dayIndex(of: timestamp, tripStartedAt: tripStartedAt) + 1
        return String.localizedStringWithFormat(String(localized: "day_chip"), day)
    }

    /// Every moment counted in one calendar's zone — a trip with no stop zones.
    static func dayLabel(for timestamp: Double, tripStartedAt: Double, calendar: Calendar = .current) -> String {
        dayLabel(for: timestamp, tripStartedAt: tripStartedAt, clock: .uniform(calendar.timeZone))
    }

    /// stop.kind hook (ADR 2026-07-18): walk visits carry their walking
    /// duration; dwells (and unknown/legacy kinds) show no detail line.
    static func walkDetail(for stop: StopRecord) -> String? {
        guard StopKind(recordValue: stop.kind) == .walkVisit, let departedAt = stop.departedAt else { return nil }
        let minutes = Int(((departedAt - stop.arrivedAt) / 60).rounded())
        return String.localizedStringWithFormat(String(localized: "recap_walk_detail"), max(minutes, 1))
    }

    /// The title card's second line. **`distanceM` is the local journey**, never
    /// the whole trip — see `localDistanceM`. On screen at 0–3 s, which is why
    /// leaving the flight in it put 9,024 km in front of a viewer before the film
    /// had started.
    static func titleSubtitle(trip: TripRecord, distanceM: Double?) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = Date(timeIntervalSince1970: trip.startedAt)
        let end = Date(timeIntervalSince1970: trip.endedAt ?? trip.startedAt)
        let dates = formatter.string(from: start, to: end)
        guard let distanceM else { return dates }
        return "\(dates) · \(Int((distanceM / 1000).rounded())) km"
    }

    /// The share payload the end-card QR would encode. **Unused by the Replay
    /// MVP** (PD-4): `kamome://route/<id>` resolves to nothing — no page, no
    /// install, no trip — so the film shows the Kamome wordmark rather than a
    /// code that invites a scan it cannot honor. Kept because the QR path is
    /// intact and returns the day the real share URL exists (spec P6/P7).
    static func shareURLString(tripId: String) -> String {
        "kamome://route/\(tripId)"
    }
}

private extension StopKind {
    /// Readers treat unknown/legacy kinds ("auto", nil) as dwell
    /// (ADR 2026-07-18 stop-kind).
    init?(recordValue: String?) {
        guard let recordValue else { return nil }
        self.init(rawValue: recordValue)
    }
}
