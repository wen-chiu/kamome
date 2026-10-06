import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine

/// **What the Footprints diary draws: an itinerary** (ADR draft
/// 2026-09-30-footprints-sits-beside-journeys, Data 1). When you went where,
/// day by day, and the photographs taken there.
///
/// One value, two sources:
/// - a found journey's comes from its cluster plan, the same plan an import
///   would store (`init(plan:config:)`);
/// - a stored trip's comes from its stored stops, which may have been edited
///   since (`init(detail:)`). For a stored trip, the stored one always wins.
///
/// It carries no kilometres and no map: those live in S3. A leg is only a
/// glyph between two places, marked by how well its line is known.
struct JourneyItinerary: Equatable {
    struct Place: Equatable, Identifiable {
        /// The stop's id; for a found journey, its position in the plan.
        let id: String
        /// Never drawn. What the place's name is looked up by (a stop point,
        /// the §0 exception).
        let lat: Double
        let lon: Double
        let arrivedAt: Double
        let departedAt: Double?
        /// The stop's name: stored, or looked up for a preview. nil until known.
        var name: String?
        let note: String?
        let photoAssetIds: [String]
    }

    /// The travel that led into a place.
    struct Leg: Equatable {
        let modes: [TransportMode]
        /// The weakest claim among its segments (`StoryLegFolding`).
        let provenance: RouteProvenance
        let isCrossing: Bool
    }

    struct Entry: Equatable, Identifiable {
        /// nil for the journey's first place.
        let leg: Leg?
        var place: Place
        var id: String { place.id }
    }

    struct Day: Equatable, Identifiable {
        /// 0-based calendar day of the journey (`TripClock`).
        let index: Int
        let date: Date
        var entries: [Entry]
        var id: Int { index }
    }

    let startedAt: Double
    let endedAt: Double
    var days: [Day]
    /// Photographs taken between places, attached to none.
    let routePhotoAssetIds: [String]
    /// The stored trip, or nil for a journey only found in the library.
    let tripId: String?
    /// What the days and times are counted in.
    let clock: TripClock

    var isStored: Bool { tripId != nil }
    var places: [Place] { days.flatMap { $0.entries.map(\.place) } }
    var photoCount: Int { places.reduce(routePhotoAssetIds.count) { $0 + $1.photoAssetIds.count } }
    var dayCount: Int { clock.dayCount(startedAt: startedAt, endedAt: endedAt) }

    /// The wall-clock time of a place, where the place is.
    func arrivalTime(of place: Place, locale: Locale = .current) -> String {
        clock.timeText(at: place.arrivedAt, locale: locale)
    }
}

// MARK: - The two sources

extension JourneyItinerary {
    /// A found journey, from the plan an import would store. Nothing about it
    /// is stored or routed, so every leg is inferred, as the stored trip's
    /// legs are until routing answers. Counted in the phone's zone: a found
    /// journey's stops have no zones until they are named.
    init(plan: ImportedTripPlan, config: TrackingConfig, clock: TripClock = .uniform()) {
        let places = plan.stops.enumerated().map { index, stop in
            Place(
                id: "plan-\(index)", lat: stop.lat, lon: stop.lon,
                arrivedAt: stop.arrivedAt, departedAt: stop.departedAt,
                name: nil, note: nil, photoAssetIds: stop.photoAssetIds
            )
        }
        let legs = plan.legs.map { leg in
            StoryLegFolding.Piece(
                startedAt: leg.startedAt,
                mode: ImportService.mode(for: leg, config: config),
                provenance: .inferred,
                isCrossing: false
            )
        }
        self.init(
            startedAt: plan.startedAt, endedAt: plan.endedAt, places: places, legs: legs,
            routePhotoAssetIds: plan.routeAttachedAssetIds, tripId: nil, clock: clock
        )
    }

    /// A stored trip, from its stored stops and segments: what S3 shows, edits
    /// included, counted in each stop's own zone.
    init(detail: TripRepository.TripDetail) {
        let photosByStop = Dictionary(grouping: detail.photos.filter { $0.stopId != nil }) { $0.stopId ?? "" }
        let places = detail.stops.map { stop in
            Place(
                id: stop.id, lat: stop.lat, lon: stop.lon,
                arrivedAt: stop.arrivedAt, departedAt: stop.departedAt,
                name: stop.name, note: stop.note,
                photoAssetIds: (photosByStop[stop.id] ?? []).map(\.phAssetId)
            )
        }
        let legs = detail.segments.map { item in
            StoryLegFolding.Piece(
                startedAt: item.segment.startedAt,
                mode: TransportMode(rawValue: item.segment.mode) ?? .unknown,
                provenance: RecapComposer.provenance(for: item.segment),
                isCrossing: RecapComposer.isCrossing(item.segment)
            )
        }
        self.init(
            startedAt: detail.trip.startedAt, endedAt: detail.trip.endedAt ?? detail.trip.startedAt,
            places: places, legs: legs,
            routePhotoAssetIds: detail.photos.filter { $0.stopId == nil }.map(\.phAssetId),
            tripId: detail.trip.id, clock: TripClock(stops: detail.stops)
        )
    }

    /// Places in order, each with the travel that led into it, grouped by the
    /// calendar day it was reached — the rule S3's diary groups by.
    private init(
        startedAt: Double, endedAt: Double, places: [Place], legs: [StoryLegFolding.Piece],
        routePhotoAssetIds: [String], tripId: String?, clock: TripClock
    ) {
        var entries: [Entry] = []
        for (index, place) in places.enumerated() {
            let leg: Leg? = index == 0 ? nil : {
                let previous = places[index - 1]
                let folded = StoryLegFolding.fold(
                    legs, from: previous.departedAt ?? previous.arrivedAt, to: place.arrivedAt
                )
                return folded.map { Leg(modes: $0.modes, provenance: $0.provenance, isCrossing: $0.isCrossing) }
            }()
            entries.append(Entry(leg: leg, place: place))
        }
        let grouped = Dictionary(grouping: entries) { clock.dayIndex(of: $0.place.arrivedAt, tripStartedAt: startedAt) }
        self.startedAt = startedAt
        self.endedAt = endedAt
        days = grouped.keys.sorted().map { day in
            Day(index: day, date: clock.date(ofDay: day, tripStartedAt: startedAt), entries: grouped[day] ?? [])
        }
        self.routePhotoAssetIds = routePhotoAssetIds
        self.tripId = tripId
        self.clock = clock
    }
}

/// **One rule for the travel between two places**, shared by S3's diary
/// (`TripDetailModel.storyLeg`) and the itinerary: every piece that starts in
/// the gap, folded into one connector. Its modes in order, its weakest claim
/// (inferred beats reconstructed beats recorded: a line is only as honest as
/// its least-known stretch), and whether any of it was a crossing.
enum StoryLegFolding {
    struct Piece: Equatable {
        let startedAt: Double
        let mode: TransportMode
        let provenance: RouteProvenance
        let isCrossing: Bool
    }

    struct Folded: Equatable {
        let modes: [TransportMode]
        let provenance: RouteProvenance
        let isCrossing: Bool
    }

    /// The pieces starting in `[from, to]`, a second's slack either side;
    /// nil when none does.
    static func fold(_ pieces: [Piece], from: Double, to: Double) -> Folded? {
        let inside = pieces.filter { $0.startedAt >= from - 1 && $0.startedAt <= to + 1 }
        guard !inside.isEmpty else { return nil }
        var modes: [TransportMode] = []
        var provenance = RouteProvenance.recorded
        var crossing = false
        for piece in inside {
            if modes.last != piece.mode { modes.append(piece.mode) }
            let claim = piece.provenance
            if claim == .inferred || (claim == .reconstructed && provenance == .recorded) { provenance = claim }
            crossing = crossing || piece.isCrossing
        }
        return Folded(modes: modes, provenance: provenance, isCrossing: crossing)
    }
}
