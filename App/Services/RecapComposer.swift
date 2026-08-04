import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
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
                provenance: provenance(for: item.segment)
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
        weighting: TrackingConfig.Export? = nil
    ) -> RecapTrip? {
        guard legs.reduce(0, { $0 + $1.coordinates.count }) >= 2 else { return nil }

        let tripStops = stops.map { stop -> RecapTrip.Stop in
            var photos = photosByStop[stop.id] ?? []
            // Stop weighting (experimental, off by default). A waypoint keeps its
            // pin and its name — the journey really did pass through — but gives
            // up its deck, and with it the park/pull-away beat, because
            // `LinearTimeline.activeScene` only counts a stop that has something
            // to reveal. Classified on the **raw** count: the deck cap is a
            // rendering decision and must not feed a judgement about the place.
            if let weighting, weighting.stopWeightingEnabled {
                let raw = rawPhotoCounts[stop.id] ?? photos.count
                let dwell = (stop.departedAt ?? stop.arrivedAt) - stop.arrivedAt
                if StopWeighting.classify(photoCount: raw, dwellS: dwell, config: weighting) == .waypoint {
                    photos = []
                }
            }
            return RecapTrip.Stop(
                coordinate: RecapCoordinate(lat: stop.lat, lon: stop.lon),
                name: stop.name ?? String(localized: "stop_unnamed"),
                dayLabel: dayLabel(for: stop.arrivedAt, tripStartedAt: trip.startedAt),
                detail: walkDetail(for: stop),
                photos: photos,
                dwellS: photos.isEmpty ? stopHoldS : deck.dwellS(photoCount: photos.count)
            )
        }

        return RecapTrip(
            legs: legs,
            stops: tripStops,
            title: trip.title,
            subtitle: titleSubtitle(trip: trip, stats: stats),
            statsLines: statsLines(stats: stats, stopCount: stops.count),
            callToAction: String(localized: "recap_end_cta"),
            shareURL: nil
        )
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

    static func titleSubtitle(trip: TripRecord, stats: TripStats?) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = Date(timeIntervalSince1970: trip.startedAt)
        let end = Date(timeIntervalSince1970: trip.endedAt ?? trip.startedAt)
        let dates = formatter.string(from: start, to: end)
        guard let stats else { return dates }
        return "\(dates) · \(Int((stats.distanceM / 1000).rounded())) km"
    }

    static func statsLines(stats: TripStats?, stopCount: Int) -> [String] {
        guard let stats else { return [] }
        let distanceStops = String.localizedStringWithFormat(
            String(localized: "recap_stat_distance_stops"),
            Int((stats.distanceM / 1000).rounded()),
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
