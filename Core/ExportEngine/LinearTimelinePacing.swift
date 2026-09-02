import Foundation
import KamomeConfig

/// **What the film's clock is worth**, split out of `LinearTimeline` on
/// 2026-09-02 to keep both files inside the size budget.
///
/// Both functions here are pure statics that take everything they need as
/// arguments — the same split `CameraPathCore` made and for the same reason:
/// nothing here touches instance state, so moving it widened no stored property
/// and cost the type no encapsulation. `private` became `static` only because
/// Swift scopes `private` to the file.
extension LinearTimeline {
    static func subjectArrival(
        plan: RecapDurationPlan?, openingS: Double, holds: [CameraPath.Hold],
        stops: [RecapTrip.Stop], config: TrackingConfig.Export
    ) -> (startS: Double, endS: Double) {
        guard plan != nil, openingS > 0 else { return (0, 0) }

        // Does the journey open *on* a stop worth presenting? That is a stop
        // whose hold begins the moment the prologue ends (so it sits at the
        // trip's origin) and which actually has photos to show.
        let opensOnStop = holds.first.flatMap { hold -> CameraPath.Hold? in
            guard hold.startS <= openingS + 0.01,
                  stops.indices.contains(hold.stopIndex),
                  !stops[hold.stopIndex].photos.isEmpty
            else { return nil }
            return hold
        }
        guard let opensOnStop else {
            // Sequence B: nothing to present, so the car arrives with the route
            // and starts driving. Anchored to the prologue's **real** end, not to
            // the configured beat times — the opening collapses beats that do not
            // move the camera, so those two numbers are not the same.
            return (max(openingS - config.zoomTransitionS, 0), openingS)
        }
        // Sequence A: the stop tells itself first, with no vehicle on screen at
        // all, and the car arrives as that scene closes — the same pull-away ramp
        // every other stop ends on.
        let park = min(config.subjectParkS, (opensOnStop.endS - opensOnStop.startS) * 0.25)
        return (max(opensOnStop.endS - park, openingS), opensOnStop.endS)
    }

    /// How long the film runs and how its time is shared out.
    ///
    /// A **story** decision, so it reads only the trip and the config — never the
    /// map. `.contentDerived` sizes the film from its own content
    /// (`RecapDurationPlan`); `.fixed` is the deterministic harness path, which
    /// wants a known length and no prologue so a golden frame means something.
    ///
    /// Either way the returned holds already carry the park beats, which are
    /// *added* around each deck rather than taken out of it.
    static func pacing(
        for trip: RecapTrip, config: TrackingConfig.Export, pacing: RecapPacing
    ) -> (plan: RecapDurationPlan?, holds: [Double]) {
        let deckPacing = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS
        )
        switch pacing {
        case .fixed:
            // No plan means `CameraPath` runs at its own `totalDurationS` with
            // `openingS` 0 — no prologue, so `zoom_transition_s` never enters the
            // opening and the subject-arrival ramp collapses to (0, 0). The stops
            // keep the dwells the trip itself carries.
            return (nil, trip.stops.map { $0.dwellS + 2 * config.subjectParkS })
        case .contentDerived:
            let plan = RecapDurationPlan.plan(
                photoCounts: trip.stops.map(\.photos.count), config: config, deck: deckPacing
            )
            let holds = trip.stops.indices.map { index in
                (index < plan.stopDwellS.count ? plan.stopDwellS[index] : trip.stops[index].dwellS)
                    + 2 * config.subjectParkS
            }
            return (plan, holds)
        }
    }

    // MARK: - The four state streams

    /// Subject motion (the route tangent) — straight from the reused CameraPath —
    /// plus the stop's **park / pull-away** presence (Chiu 2026-07-26).
    ///
    /// The car arrives at the stop, parks, and is gone while the stop tells its
    /// own story; it returns as the next leg begins. Before this, the car sat
    /// parked on the map for the whole hold and the stop's pin had to be shoved
    /// aside to avoid printing text across it — which put the pin kilometres from
    /// the place it was marking. Removing the car during the stop is what lets the
    /// pin sit exactly where the journey actually paused.

    /// Each leg's window of the concatenated polyline, in travel order.
    static func legWindows(of legs: [RecapTrip.Leg]) -> [LegRange] {
        var offset = 0
        return legs.map { leg in
            let range = offset..<(offset + leg.coordinates.count)
            offset = range.upperBound
            return LegRange(
                range: range, mode: leg.mode, provenance: leg.provenance, isCrossing: leg.isCrossing
            )
        }
    }
}
