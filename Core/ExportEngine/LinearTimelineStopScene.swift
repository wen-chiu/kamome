import Foundation
import KamomeConfig

/// The stop scene's choreography, split out of `LinearTimeline` to keep both
/// files inside the size budget. Everything here is overlay and subject timing —
/// the camera holds its fixed frame throughout (Chiu 2026-07-25), and nothing in
/// this file touches it.
extension LinearTimeline {
    // MARK: - Stop choreography (overlay + subject — the camera still holds still)

    /// The stop scene playing at `time`, if any. A hold only counts as a scene
    /// when its stop has something to reveal — the subject and the overlays both
    /// read this, so the car can never park for a stop that draws nothing.
    func activeScene(atTime time: Double) -> (hold: CameraPath.Hold, stop: RecapTrip.Stop)? {
        for hold in holds where hold.startS <= time && time < hold.endS {
            guard stops.indices.contains(hold.stopIndex) else { continue }
            let stop = stops[hold.stopIndex]
            guard !stop.photos.isEmpty else { return nil }
            return (hold, stop)
        }
        return nil
    }

    /// The stop the film is **parked at**, if any — unlike `activeScene`, this
    /// does not require the stop to have photos. The HUD names where the vehicle
    /// is, and a stop with nothing to show is still a place the journey stopped;
    /// on the road between stops it is nil and the HUD shows the day alone.
    func holdingStop(atTime time: Double) -> RecapTrip.Stop? {
        for hold in holds where hold.startS <= time && time < hold.endS {
            guard stops.indices.contains(hold.stopIndex) else { continue }
            return stops[hold.stopIndex]
        }
        return nil
    }

    /// Which day of the trip the film is on: the day of the **most recent stop
    /// reached**, held until the next one is.
    ///
    /// A leg belongs to no stop, so it has to inherit a day from one of them, and
    /// inheriting from the stop just left is the honest direction — you drive on
    /// the day you set out, and the counter turns over on arrival, not somewhere
    /// out on the road. Before the first stop the trip is on its first day.
    func dayLabel(atTime time: Double) -> String {
        var label = stops.first?.dayLabel ?? ""
        for hold in holds where hold.startS <= time {
            guard stops.indices.contains(hold.stopIndex) else { continue }
            label = stops[hold.stopIndex].dayLabel
        }
        return label
    }

    /// The deck's sub-window inside a stop's hold. The scene runs
    /// **park → label → deck → pull away**, so the card opens after the car has
    /// finished parking plus `labelLeadS`, and — importantly — *closes before the
    /// car comes back*. Without that last reservation the card is still covering
    /// the spot while the vehicle fades in behind it, and the departure never
    /// reads on screen.
    func deckWindow(_ hold: CameraPath.Hold) -> (start: Double, end: Double) {
        let park = parkRamp(hold)
        let end = max(hold.endS - park, hold.startS)
        return (min(hold.startS + park + deck.labelLeadS, end), end)
    }

    /// The zoom ramp used at both edges of a deck window, clamped to 40% of the
    /// window so it always fits even when a stop-dense trip squeezed the hold
    /// (`max_hold_fraction`).
    func zoomRamp(_ window: (start: Double, end: Double)) -> Double {
        min(deck.zoomS, (window.end - window.start) * 0.4)
    }

    /// **Card** envelope (Chiu 2026-07-25): the photo keeps growing across the
    /// whole hold — not just the camera's dolly-in — so the stop plays as a slow
    /// cinematic reveal rather than a card that pops to full size and sits
    /// there. It scales back down over the closing ramp as the scene closes.
    func deckReveal(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let zoom = zoomRamp(window)
        let openEnd = window.end - zoom
        let opening = openEnd - window.start
        guard opening > 0 else { return 0 }
        if time <= openEnd {
            // The card blooms: it rises quickly, passes full size, and settles
            // back — an arrival rather than a grow. The overshoot decays across
            // the opening so the card is exactly at rest by the time it holds.
            let progress = (time - window.start) / opening
            let eased = Self.smoothstep(progress)
            let overshoot = sin(min(max(progress, 0), 1) * .pi) * Self.deckBloomOvershoot
            return eased + overshoot * (1 - eased)
        }
        guard zoom > 0 else { return 0 }
        return Self.smoothstep((window.end - time) / zoom)
    }

    /// Peak of the bloom past full size, as a fraction. Matches the renderer's
    /// `deckRevealOvershoot` ceiling; the style clamps to it.
    private static let deckBloomOvershoot = 0.06

    /// Card opacity: fades in over the opening ramp, out over the closing one.
    func deckOpacity(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let zoom = zoomRamp(window)
        guard zoom > 0 else { return time >= window.start ? 1 : 0 }
        if time < window.start + zoom { return Self.smoothstep((time - window.start) / zoom) }
        if time > window.end - zoom { return Self.smoothstep((window.end - time) / zoom) }
        return 1
    }

    /// The stop's pin and name. It **fades up exactly as the car parks**, so the
    /// stop's identity is handed from the vehicle to the pin at the same place
    /// rather than appearing somewhere else on the map; solid through the rest of
    /// beat 1; then handed on again to the card's own pin + name as the deck
    /// opens.
    func leadLabelOpacity(
        atTime time: Double, hold: CameraPath.Hold, deck window: (start: Double, end: Double)
    ) -> Double {
        // When the film opens on this stop there is no car to hand off from, so
        // the pin simply fades up on the same ramp rather than cross-fading with
        // a vehicle that was never drawn.
        let park = parkRamp(hold)
        let arriving = park > 0 ? Self.smoothstep((time - hold.startS) / park) : 1
        guard time >= window.start else { return arriving }
        let zoom = zoomRamp(window)
        guard zoom > 0 else { return 0 }
        return min(arriving, 1 - Self.smoothstep((time - window.start) / zoom))
    }

    /// Which photo is in focus: the rotate phase (between the zoom edges) split
    /// into `count` equal slots. Grow holds photo 0 (highlight leads); shrink
    /// holds the last.
    func focusIndex(atTime time: Double, deck window: (start: Double, end: Double), count: Int) -> Int {
        let zoom = zoomRamp(window)
        let rotateStart = window.start + zoom
        let rotateLength = max((window.end - zoom) - rotateStart, 1e-6)
        let slot = rotateLength / Double(count)
        return min(max(Int((time - rotateStart) / slot), 0), count - 1)
    }
}
