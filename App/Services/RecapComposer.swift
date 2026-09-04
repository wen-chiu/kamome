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
        case .exif, .timeline: return .inferred
        }
    }

    /// Whether this segment is a **crossing**: routing answered, and the answer
    /// was that no road joins its ends (`Docs/camera-arcs.md` §0).
    ///
    /// One stored verdict and nothing else — no distance, no mode, no endpoint
    /// name. NULL (nobody asked, routing disabled, the provider never answered)
    /// is `false`, because the honest reading of "we do not know" is "do not fly
    /// a sprite over it".
    static func isCrossing(_ segment: SegmentRecord) -> Bool {
        segment.routeVerdict == .noRoad
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
    /// `photosByStop` maps stop id → the stop's selected deck photo *refs*
    /// (highlight first, ≤ `deck_max_photos`) — refs, not bitmaps; the render
    /// layer resolves them. `deck` + `stopHoldS` size each stop's dwell from its
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
        weighting: TrackingConfig.Export? = nil,
        everyLegRoutabilityEstablished: Bool = false
    ) -> RecapTrip? {
        guard legs.reduce(0, { $0 + $1.coordinates.count }) >= 2 else { return nil }

        let selection = select(stops: stops, photosByStop: photosByStop,
                               rawPhotoCounts: rawPhotoCounts, favoriteCounts: favoriteCounts,
                               weighting: weighting)
        let kept = selection.kept
        let allocation = selection.allocation

        let tripStops = kept.map { stop -> RecapTrip.Stop in
            var photos = photosByStop[stop.id] ?? []
            if let allocated = allocation[stop.id] {
                photos = Array(photos.prefix(allocated))
            }
            // Stop weighting: an independent legacy flag, shipping `false`, that
            // survives the mode migration by explicit decision (HANDOFF). Measured
            // as having no reachable effect beyond what the modes already do.
            if let weighting, weighting.stopWeightingEnabled {
                let raw = rawPhotoCounts[stop.id] ?? photos.count
                let dwell = (stop.departedAt ?? stop.arrivedAt) - stop.arrivedAt
                if StopWeighting.classify(photoCount: raw, dwellS: dwell, config: weighting) == .waypoint {
                    photos = []
                }
            }
            return RecapTrip.Stop(
                coordinate: snapped(lat: stop.lat, lon: stop.lon, to: legs),
                name: stop.name ?? String(localized: "stop_unnamed"),
                dayLabel: dayLabel(for: stop.arrivedAt, tripStartedAt: trip.startedAt),
                detail: walkDetail(for: stop),
                photos: photos,
                dwellS: photos.isEmpty ? stopHoldS : deck.dwellS(photoCount: photos.count)
            )
        }

        // **Every kilometre the film shows a viewer is the local journey**
        // (Chiu 2026-09-02). One number, computed once, feeding both surfaces —
        // the title card's subtitle and the end card's stats — because fixing one
        // of the three and not the others is exactly how 9,024 km survived on two
        // cards after the odometer was corrected.
        let localM = localDistanceM(stats: stats, legs: legs)
        return RecapTrip(
            legs: legs,
            stops: tripStops,
            title: trip.title,
            subtitle: titleSubtitle(trip: trip, distanceM: localM),
            statsLines: statsLines(stats: stats, distanceM: localM, stopCount: stops.count),
            callToAction: String(localized: "recap_end_cta"),
            shareURL: nil,
            journeyDates: journeyDates(trip),
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

    /// Which stops the film presents, and how many photographs each shows.
    ///
    /// **One switch, one decision.** This used to be three conditionals over three
    /// booleans, each carrying a negation of the others. Exhaustive with no
    /// `default:` on purpose: adding a `RecapMode` case must break the build here
    /// rather than fall silently into an existing branch.
    private static func select(
        stops: [StopRecord],
        photosByStop: [String: [PhotoRef]],
        rawPhotoCounts: [String: Int],
        favoriteCounts: [String: Int],
        weighting: TrackingConfig.Export?
    ) -> (kept: [StopRecord], allocation: [String: Int]) {
        guard let weighting else { return (stops, [:]) }
        let signals = stops.map { stop in
            StopPhotoAllocator.Signal(
                photoCount: rawPhotoCounts[stop.id] ?? (photosByStop[stop.id]?.count ?? 0),
                favoriteCount: favoriteCounts[stop.id] ?? 0
            )
        }
        var allocation: [String: Int] = [:]
        switch weighting.recapMode {
        case .highlight:
            // A skipped stop leaves the film entirely — no pin, no name, no pause,
            // no park beat.
            // The trip earns its stop count from its own size (Chiu 2026-08-14).
            // This used to pass `totalDurationMaxS`, which is why every trip
            // presented the same 8 stops whether it had 10 or 65: the duration
            // ceiling was the same for all of them.
            let tiers = StopPhotoAllocator.triage(signals, config: weighting)
            let kept = zip(stops, tiers).compactMap { stop, tier -> StopRecord? in
                guard let tier else { return nil }
                allocation[stop.id] = tier
                return stop
            }
            return (kept, allocation)
        case .full:
            // Every stop survives; rank decides how many photographs it shows.
            let counts = StopPhotoAllocator.allocate(signals, config: weighting)
            for (stop, count) in zip(stops, counts) { allocation[stop.id] = count }
            return (stops, allocation)
        }
    }

    /// Same day math as S3's filter chips (TripDetailModel.dayIndex).
    static func dayLabel(for timestamp: Double, tripStartedAt: Double) -> String {
        let day = Int((timestamp - tripStartedAt) / 86_400) + 1
        return String.localizedStringWithFormat(String(localized: "day_chip"), day)
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

    /// The end card's stats. **`distanceM` is the local journey**, for the same
    /// reason and from the same source as the subtitle above.
    static func statsLines(stats: TripStats?, distanceM: Double?, stopCount: Int) -> [String] {
        guard let stats, let distanceM else { return [] }
        let distanceStops = String.localizedStringWithFormat(
            String(localized: "recap_stat_distance_stops"),
            Int((distanceM / 1000).rounded()),
            stopCount
        )
        let drive = String.localizedStringWithFormat(
            String(localized: "recap_stat_drive"),
            String(format: "%.1f", stats.driveS / 3600)
        )
        return [distanceStops, drive]
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
