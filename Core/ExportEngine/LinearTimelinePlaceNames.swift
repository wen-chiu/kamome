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
/// film's stops is in (`RecapTrip.Stop.locality`) — or each part of the town,
/// for a journey that never leaves one — once, at the stop nearest the middle
/// of its stops.
/// Nothing is looked up, and nothing is named that the trip did not stop in.
/// The renderer keeps overlapping names apart; the order here says which one
/// wins.
extension LinearTimeline {
    /// The names the film draws, the place it stays in longest first, then in
    /// film order.
    ///
    /// **A town, unless the journey never leaves one** (Chiu 2026-10-02, #183:
    /// 「標更細的地名」). A film that stays in one municipality had one name, and
    /// its close frames none. Such a journey is named by the parts of its town
    /// (`subLocality`) — when its stops are in two or more of them; one part
    /// is no finer than the town, and less known. `journeys` says which
    /// journey each stop is in: each side of a crossing is its own.
    static func placeNames(of stops: [RecapTrip.Stop], journeys: [Int]? = nil) -> [RecapPlaceName] {
        /// One place's stops.
        struct Place {
            let first: Int
            var members: [RecapCoordinate] = []
            var dwellS = 0.0

            /// **The stop nearest the middle of the place's stops** — a stop,
            /// not the middle itself: the middle of two stops on a curved coast
            /// is in the sea, and a town is not named out there.
            var anchor: RecapCoordinate {
                let lat = members.reduce(0) { $0 + $1.lat } / Double(members.count)
                let lon = members.reduce(0) { $0 + $1.lon } / Double(members.count)
                let east = cos(lat * .pi / 180)
                func apart(_ point: RecapCoordinate) -> Double {
                    hypot(point.lat - lat, (point.lon - lon) * east)
                }
                return members.min { apart($0) < apart($1) } ?? RecapCoordinate(lat: lat, lon: lon)
            }
        }
        func text(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        let journey = journeys ?? stops.map { _ in 0 }
        // The journeys that never leave one town, and have parts to tell apart.
        let fine = Set(Set(journey).filter { index in
            let own = stops.indices.filter { journey[$0] == index }
            return Set(own.compactMap { text(stops[$0].locality) }).count == 1
                && Set(own.compactMap { text(stops[$0].subLocality) }).count > 1
        })
        var places: [String: Place] = [:]
        for (index, stop) in stops.enumerated() {
            let town = text(stop.locality)
            guard let name = fine.contains(journey[index]) ? text(stop.subLocality) ?? town : town else { continue }
            var place = places[name] ?? Place(first: index)
            place.members.append(stop.coordinate)
            place.dwellS += stop.dwellS
            places[name] = place
        }
        return places.sorted { lhs, rhs in
            lhs.value.dwellS != rhs.value.dwellS ? lhs.value.dwellS > rhs.value.dwellS : lhs.value.first < rhs.value.first
        }.map { RecapPlaceName(name: $0.key, coordinate: $0.value.anchor) }
    }

    /// Which journey each stop is in: how many crossings have played by the time
    /// the film holds at it. A stop the film never holds at is in the first.
    var stopJourneys: [Int] {
        var journeys = stops.map { _ in 0 }
        for hold in holds where journeys.indices.contains(hold.stopIndex) {
            journeys[hold.stopIndex] = path.crossingBeatWindowsS.filter { $0.upperBound <= hold.startS }.count
        }
        return journeys
    }

    /// The name a stop is being presented under at `time`, and how strongly:
    /// its lead-in label, then its photo deck, or a quiet stop's passing label.
    func presentedStopName(atTime time: Double) -> (name: String, opacity: Double)? {
        if let active = activeScene(atTime: time) {
            guard let name = displayName(of: active.hold.stopIndex) else { return nil }
            let window = deckWindow(active.hold)
            let deck = time >= window.start ? deckOpacity(atTime: time, deck: window) : 0
            return (name, max(leadLabelOpacity(atTime: time, hold: active.hold, deck: window), deck))
        }
        guard let quiet = quietStop(atTime: time), let name = displayName(of: quiet.hold.stopIndex) else { return nil }
        return (name, quietLabelOpacity(atTime: time, hold: quiet.hold))
    }

    /// The names, for the whole body of the film: they come up as the title
    /// card's frame zooms into the journey, and stay through the end reveal —
    /// the whole route, with the places it went. Never under the end card, and
    /// never over a flight: that frame has its two ends named already, and
    /// every town of the destination sits on one point of it.
    func placeNamesContent(atTime time: Double) -> OverlayContent? {
        guard time >= titleCardS, time < durationS - endCardS else { return nil }
        var names = Self.placeNames(of: stops, journeys: stopJourneys)
        // A stop presenting itself under a town's name takes the name over:
        // the town's fades out as the stop's comes up, and back as it leaves.
        if let shown = presentedStopName(atTime: time),
           let index = names.firstIndex(where: { $0.name == shown.name }) {
            names[index].opacity = 1 - shown.opacity
        }
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
