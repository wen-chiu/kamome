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
        guard let journey = destinationJourney(
            legs: trip.legs, stops: trip.stops, config: config
        ) else { return trip }
        return RecapTrip(
            legs: journey.legs,
            stops: journey.stops,
            title: trip.title,
            subtitle: trip.subtitle,
            endCardFigures: trip.endCardFigures,
            shareURL: trip.shareURL,
            journeyDates: trip.journeyDates,
            everyLegRoutabilityEstablished: trip.everyLegRoutabilityEstablished
        )
    }

    /// **The legs and stops the destination half keeps** — the trim itself, with
    /// no `RecapTrip` around it. nil when there is nothing to remove.
    ///
    /// 🔴 **Split out on 2026-09-05 so there is exactly one implementation of
    /// "which journey does this film tell".** The closing card has to count the
    /// stops of the *film's* journey rather than the whole trip's
    /// (Chiu 2026-09-05), and it is composed in the app layer before any
    /// `RecapTrip` exists to trim — so it asks this. Re-deriving the rule there
    /// is precisely how the card came to claim a journey the film does not show:
    /// `RecapComposer` counted the whole trip and `LinearTimeline` trimmed it
    /// afterwards, and nothing made the two agree.
    public static func destinationJourney(
        legs: [RecapTrip.Leg], stops: [RecapTrip.Stop], config: TrackingConfig.Export
    ) -> (legs: [RecapTrip.Leg], stops: [RecapTrip.Stop])? {
        guard let crossing = legs.firstIndex(where: \.isCrossing), crossing > 0 else { return nil }
        guard let departure = legs[crossing].coordinates.first else { return nil }

        // The departure is the stop nearest the crossing's first vertex. Nearest
        // rather than "the last stop before it in the list", because a stop list
        // that has been through selection may not contain every cluster, and the
        // one the film should open on is the one the flight actually leaves from.
        let keepFrom = stops.indices.min(by: { lhs, rhs in
            distanceM(stops[lhs].coordinate, departure) < distanceM(stops[rhs].coordinate, departure)
        })
        let kept = keepFrom.map { Array(stops[$0...]) } ?? stops
        return (Array(legs[crossing...]), cappedDeparture(kept, config: config))
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
            dwellS: photos.isEmpty ? config.stopHoldS : deck.dwellS(photoCount: photos.count),
            locality: departure.locality
        )] + stops.dropFirst()
    }

    /// **Where the trip starts home** — the index of the first leg of the flight
    /// back, or nil when the trip never comes home.
    ///
    /// ADR 2026-09-01 decided it and nothing built it: *"The film ends at the
    /// destination. There is no return flight. The import carries the homeward
    /// leg and its photographs; the film does not."* Until 2026-09-23 the film
    /// kept everything after the outbound crossing, so a round trip drew the
    /// flight home, and the body camera — which frames the whole route it is
    /// given — held Taiwan in shot for the entire Miyakojima film (Chiu's device
    /// film, 2026-09-23).
    ///
    /// ## The rule
    ///
    /// **Home is the ground the trip left from**: every vertex before the
    /// outbound crossing, and that crossing's first vertex. A later crossing
    /// **lands home** when its last vertex is within `homeRadiusM` of that
    /// ground. The first such crossing is the flight home — and if the legs
    /// immediately before it are crossings that landed *away* from the
    /// destination (a transit: Miyakojima → Naha → Taoyuan, with nothing but an
    /// airport photograph at Naha), the homecoming starts at the first of them.
    /// A crossing that landed on the destination's own ground — a beach
    /// photograph routing answered "no road" for — is the trip, and stops the
    /// walk. It never reaches back into the outbound crossing itself.
    ///
    /// **`homeRadiusM` is `discovery.away_radius_m`**, passed in by the caller —
    /// the product's one existing definition of *away from home* (ADR
    /// 2026-09-17). Not a new number, and not a second meaning for an old one:
    /// the question here is literally "is this home or away?". It is what lets
    /// Taoyuan-out, Songshan-back (35 km) count as home.
    ///
    /// ## Why not "nearer home than the destination"
    ///
    /// A scale-free comparison was the first candidate and it is wrong on real
    /// trips: Taipei → Naha → Ishigaki lands **nearer Taipei than Naha**, and
    /// would have cut the film at the transit. A point of departure has no extent
    /// of its own, so "home" needs a size, and the product already has one.
    ///
    /// ⚠️ **What this leaves in, knowingly:** flying home to a different city
    /// (Kaohsiung after leaving from Taoyuan) is not *home* by this rule, and that
    /// film keeps its last flight. Honest — it is a journey to a place the trip
    /// did not start — and cheap to revisit with a render if Chiu wants it gone.
    public static func homecomingLegIndex(legs: [RecapTrip.Leg], homeRadiusM: Double) -> Int? {
        guard let outbound = legs.firstIndex(where: \.isCrossing),
              let departure = legs[outbound].coordinates.first else { return nil }
        let home = legs[..<outbound].flatMap(\.coordinates) + [departure]
        guard let flightHome = legs.indices.first(where: { index in
            guard index > outbound, legs[index].isCrossing,
                  let landing = legs[index].coordinates.last else { return false }
            return home.contains { distanceM($0, landing) <= homeRadiusM }
        }) else { return nil }
        // Walk back over a transit — a crossing that landed somewhere *away* from
        // the destination, with no journey of its own. A crossing that landed on
        // the destination's own ground (a beach photograph, answered "no road")
        // is part of the trip and stops the walk.
        // The destination is the ground travelled there — not the outbound
        // landing, which on a trip out through a transit is the transit.
        let travelled = legs[(outbound + 1)..<flightHome].filter { !$0.isCrossing }.flatMap(\.coordinates)
        let destination = travelled.isEmpty ? Array(legs[flightHome].coordinates.prefix(1)) : travelled
        var start = flightHome
        while start - 1 > outbound, legs[start - 1].isCrossing,
              let landing = legs[start - 1].coordinates.last,
              !destination.contains(where: { distanceM($0, landing) <= homeRadiusM }) {
            start -= 1
        }
        return start
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
