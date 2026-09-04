import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **The trip as a type-2 film tells it: the origin's drive is not in the
/// recap** (Chiu 2026-09-01).
///
/// A journey out to somewhere else is a film about the somewhere else. The drive
/// to the airport is not what the trip was about, and framing it costs the
/// destination twice over — once in screen time, and once in the body span,
/// which is derived from whichever local journey the opening establishes.
///
/// **The departure's photographs stay, but only one or two of them.** They are
/// the trip's beginning as the traveller lived it, so the last stop before the
/// crossing — in practice the departure airport, named by `StopNamer` like any
/// other stop — survives the trim. Everything before it does not, and its deck is
/// capped at `export.departure_stop_max_photos` (Chiu 2026-09-02): an airport is
/// in the film because the trip began there, not because it is a place worth a
/// full deck, and at the flight frame's scale its pin is sub-pixel anyway.
///
/// ## What this produces, and why that is the point
///
/// The trimmed trip **begins with the crossing**, which is exactly
/// `Docs/camera-arcs.md` §4 **Case C** — the shape that document predicted
/// ("photographs start at the departure airport, so segment 1 is one point") and
/// left unbuilt. Its rule is followed here: *when the first local journey is
/// degenerate, the opening arc **is** the first crossing arc.* The film opens at
/// the apex with both places on screen, the sprite crosses, and the camera closes
/// into the destination. One move, not two.
///
/// ⚠️ **This supersedes §4 Case B's reasoning for a type-2 film.** Case B says the
/// film opens on the departure because "you cannot arrive somewhere if the film
/// never showed you leaving". That is still true, and it is now the *departure
/// airport's photographs and the flight frame* that show the leaving, rather than
/// a drive across the origin city. The doc is stale on this point rather than
/// wrong about the principle.
public enum RecapTypeTwoFilm {
    /// The trip with its origin journey removed, or unchanged when there is
    /// nothing to remove.
    ///
    /// Unchanged when the trip has no crossing, or when the crossing is already
    /// the first leg — a trip that begins at the airport needs no trimming and
    /// must not be trimmed twice.
    public static func trimmedToTheDestination(
        _ trip: RecapTrip, config: TrackingConfig.Export
    ) -> RecapTrip {
        guard let crossing = trip.legs.firstIndex(where: \.isCrossing), crossing > 0 else {
            return trip
        }
        guard let departure = trip.legs[crossing].coordinates.first else { return trip }

        // The departure is the stop nearest the crossing's first vertex. Nearest
        // rather than "the last stop before it in the list", because a stop list
        // that has been through selection may not contain every cluster, and the
        // one the film should open on is the one the flight actually leaves from.
        let keepFrom = trip.stops.indices.min(by: { lhs, rhs in
            distanceM(trip.stops[lhs].coordinate, departure)
                < distanceM(trip.stops[rhs].coordinate, departure)
        })
        let kept = keepFrom.map { Array(trip.stops[$0...]) } ?? trip.stops

        return RecapTrip(
            legs: Array(trip.legs[crossing...]),
            stops: cappedDeparture(kept, config: config),
            title: trip.title,
            subtitle: trip.subtitle,
            statsLines: trip.statsLines,
            callToAction: trip.callToAction,
            shareURL: trip.shareURL,
            journeyDates: trip.journeyDates,
            everyLegRoutabilityEstablished: trip.everyLegRoutabilityEstablished
        )
    }

    /// The kept stops with the **first** one — the departure airport — holding at
    /// most `export.departure_stop_max_photos` photographs.
    ///
    /// **The dwell is repriced, not only the deck.** `Stop.dwellS` is a fact about
    /// the stop derived from its own photo count (`RecapDeck.dwellS`), so leaving a
    /// three-photograph dwell on a two-photograph stop would be a stored value
    /// lying about itself. Content-derived pacing never reads it — it reprices from
    /// `photos.count` *after* this trim — but `.fixed` pacing does, and the two
    /// must not disagree about the same stop.
    ///
    /// **No duration is written here, deliberately.** The beat that results is
    /// whatever `RecapDurationPlan` prices two photographs at. Hard-coding the
    /// review's ~3 s would be a second pacing model beside the one that exists to
    /// make duration follow content.
    private static func cappedDeparture(
        _ stops: [RecapTrip.Stop], config: TrackingConfig.Export
    ) -> [RecapTrip.Stop] {
        guard config.departureStopMaxPhotos >= 0, let departure = stops.first,
              departure.photos.count > config.departureStopMaxPhotos else { return stops }
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let photos = Array(departure.photos.prefix(config.departureStopMaxPhotos))
        return [RecapTrip.Stop(
            coordinate: departure.coordinate,
            name: departure.name,
            dayLabel: departure.dayLabel,
            detail: departure.detail,
            photos: photos,
            dwellS: photos.isEmpty ? config.stopHoldS : deck.dwellS(photoCount: photos.count)
        )] + stops.dropFirst()
    }

    /// The two ends of the flight — what the opening frame has to hold.
    ///
    /// nil for a trip with no crossing, which is every local film.
    public static func crossingEnds(
        _ trip: RecapTrip
    ) -> (origin: RecapCoordinate, destination: RecapCoordinate)? {
        guard let crossing = trip.legs.first(where: \.isCrossing),
              let origin = crossing.coordinates.first,
              let destination = crossing.coordinates.last,
              origin != destination else { return nil }
        return (origin, destination)
    }

    private static func distanceM(_ lhs: RecapCoordinate, _ rhs: RecapCoordinate) -> Double {
        Geo.distanceM(latA: lhs.lat, lonA: lhs.lon, latB: rhs.lat, lonB: rhs.lon)
    }
}
