import Foundation

/// **The film names the trip's own towns on the map** (Chiu 2026-10-02, ADR
/// file 2026-10-02 — the map-labels lock, reopened by name).
///
/// Chiu, on his New Zealand film: *「地名放大一點 使用者比較能知道自己在哪裡」*. The
/// base map's own names cannot answer that. Their size and their zoom threshold
/// belong to the map's place classes, not to the trip: the village a film stays
/// in is drawn at 10 px, below the peaks around it, and not at all once the
/// frame is wide enough to show the road there.
///
/// So the names are Kamome's, and they are the trip's: each town one of the
/// film's stops is in (`RecapTrip.Stop.locality`), once, at the middle of its
/// stops. Nothing is looked up, and nothing is named that the trip did not stop
/// in. The renderer keeps overlapping names apart; the order here says which
/// one wins.
extension LinearTimeline {
    /// The towns the film's stops are in, the one the film stays in longest
    /// first, then in film order.
    static func placeNames(of stops: [RecapTrip.Stop]) -> [RecapPlaceName] {
        /// One town's stops, summed.
        struct Town {
            let first: Int
            var lat = 0.0, lon = 0.0, count = 0.0, dwellS = 0.0
        }
        var towns: [String: Town] = [:]
        for (index, stop) in stops.enumerated() {
            guard let name = stop.locality, !name.isEmpty else { continue }
            var town = towns[name] ?? Town(first: index)
            town.lat += stop.coordinate.lat
            town.lon += stop.coordinate.lon
            town.count += 1
            town.dwellS += stop.dwellS
            towns[name] = town
        }
        return towns.sorted { lhs, rhs in
            lhs.value.dwellS != rhs.value.dwellS ? lhs.value.dwellS > rhs.value.dwellS : lhs.value.first < rhs.value.first
        }.map { name, town in
            RecapPlaceName(name: name, coordinate: RecapCoordinate(lat: town.lat / town.count, lon: town.lon / town.count))
        }
    }

    /// The names, for the whole body of the film: they come up as the title
    /// card's frame zooms into the journey, and stay through the end reveal —
    /// the whole route, with the places it went. Never under the end card, and
    /// never over a flight: that frame has its two ends named already, and
    /// every town of the destination sits on one point of it.
    func placeNamesContent(atTime time: Double) -> OverlayContent? {
        guard time >= titleCardS, time < durationS - endCardS else { return nil }
        let names = Self.placeNames(of: stops)
        guard !names.isEmpty else { return nil }
        let rise = journeyStartS > titleCardS
            ? Self.smoothstep((time - titleCardS) / (journeyStartS - titleCardS)) : 1
        var flight = 0.0
        if case let .flightEnds(_, _, opacity)? = flightEnds(atTime: time) { flight = opacity }
        let pass = journeyCardContent(atTime: time)?.opacity ?? 0
        let opacity = rise * (1 - flight) * (1 - pass)
        return opacity > 0.001 ? .placeNames(names, opacity: opacity) : nil
    }
}
