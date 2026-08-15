import Foundation
import KamomeConfig

/// What a stop is worth to the film (**EXPERIMENTAL**, Chiu 2026-08-04).
///
/// Not every place a journey pauses is a place worth watching. A supermarket, a
/// petrol station, a roadside toilet — the trip really did stop there, and the
/// route should say so, but the film has no reason to hold on it. Until now every
/// stop was treated identically, so on a 65-stop trip the eight seconds spent
/// presenting a fuel stop came out of the eight minutes at a glacier.
///
/// **The heuristic, and why.** A stop is a *waypoint* when it has at most
/// `waypoint_max_photos` photographs **and** was over inside
/// `waypoint_max_dwell_s`. Both conditions, on purpose:
///
/// - *Photograph count is the honest signal of attention.* You photograph what
///   you came to see. It needs no new data — the importer already clusters by it.
/// - *Duration alone is not enough.* A long lunch you barely photographed is
///   still a place you chose to be, and demoting it on photo count alone would
///   quietly delete the meals from a road trip.
/// - Requiring both keeps the rule conservative: it only ever demotes stops that
///   are *both* thin and brief, which is what a fuel stop actually looks like.
///
/// **What the real trips do under it** (2026-08-04, measured): Iceland demotes 8
/// of 65 stops, New Zealand 1 of 20. So this is necessary but nowhere near
/// sufficient on its own — the photo-count distribution on a real trip is
/// enormously skewed (Iceland's stops run from 2 to 252 photographs), and the
/// bulk of the pressure is the sheer stop count, not the thin stops. Read this
/// alongside the duration rule, never as a replacement for it.
public enum StopWeight: Equatable {
    /// Worth presenting: pin, name, photo deck, the car parks.
    case highlight
    /// A point on the route. No deck, no park — the journey passes through.
    case waypoint
}

public enum StopWeighting {
    /// Classifies one stop from data the importer already has.
    ///
    /// `photoCount` is the stop's **raw** photograph count, not its selected deck
    /// size — the deck is capped at `deck_max_photos`, and a cap is a rendering
    /// decision that must not feed back into a judgement about the place.
    public static func classify(
        photoCount: Int, dwellS: Double, config: TrackingConfig.Export
    ) -> StopWeight {
        guard config.stopWeightingEnabled else { return .highlight }
        let thin = photoCount <= config.waypointMaxPhotos
        let brief = dwellS < config.waypointMaxDwellS
        return thin && brief ? .waypoint : .highlight
    }
}
