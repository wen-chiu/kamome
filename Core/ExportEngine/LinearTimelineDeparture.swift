import Foundation

/// **Where the journey set out, named over the opening** (Chiu 2026-11-03).
///
/// The highlight cut drops the stops it gives no photographs, and a trip's
/// first stop is often one of them: the airport, the first night's hotel. The
/// film then opened with the car waiting on an unmarked point while the map
/// already named the trip's towns (ADR 2026-10-02, kept from the opening by
/// Chiu 2026-10-29) — so the first place named was one the trip reaches later,
/// and Chiu's Iceland film read as setting out from the capital it came back
/// to at the end. The HUD said the same: the first stop's day and town, before
/// the car had left.
///
/// So the departure gets a quiet stop's label — its pin and its name, the same
/// drawing — while the car waits there: up as the car fades in, down over
/// `deck_zoom_s` once it sets off. No pause, no new tunable, and the film's
/// length is unchanged. Until the first stop the HUD carries its day and town.
///
/// Never on a type-2 film: its departure airport is never named (ADR
/// 2026-09-05 (c)), and the trim leaves no departure to name.
extension LinearTimeline {
    /// How strongly the departure's label is drawn at `time`. Zero when a stop
    /// begins before the label would be gone — that stop is at the start and
    /// names it — and on a route-only film, which draws no stop's label
    /// (`quietStop`).
    func departureLabelOpacity(atTime time: Double) -> Double {
        guard departure != nil, time >= titleCardS, stops.contains(where: { !$0.photos.isEmpty }) else { return 0 }
        let leaves = journeyStartS + deck.zoomS
        if let first = holds.first, first.startS < leaves { return 0 }
        let rise = subjectArrivalEndS > subjectArrivalStartS
            ? Self.smoothstep((time - subjectArrivalStartS) / (subjectArrivalEndS - subjectArrivalStartS)) : 1
        let fall = deck.zoomS > 0 ? 1 - Self.smoothstep((time - journeyStartS) / deck.zoomS) : (time < journeyStartS ? 1 : 0)
        return rise * fall
    }

    /// The departure's pin and name, while they are up.
    func departureLabel(atTime time: Double) -> OverlayContent? {
        guard let departure else { return nil }
        let opacity = departureLabelOpacity(atTime: time)
        guard opacity > 0.001 else { return nil }
        return .stopLabel(
            name: departure.name, coordinate: departure.coordinate, detail: departure.detail, opacity: opacity
        )
    }
}
