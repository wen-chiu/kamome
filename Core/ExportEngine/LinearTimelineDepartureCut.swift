import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **A flight the film does not draw is cut, not flown** (Chiu 2026-10-10,
/// #275, ADR file 2026-10-10).
///
/// Past `crossing_flight_max_longitude_deg` the type-2 film takes its frozen-card
/// form (`CrossingFraming`): the title card sits over a frozen frame of the
/// destination, and the film cuts into the local trip. Until this, the trim kept
/// the departure stop and the crossing for both forms, so the frozen-card film
/// was a drawn-flight film without its opening — the camera swept back to the
/// departure airport, flew a 7,300 km arc mid-film and ended on a reveal wider
/// than the world, at 4.5 snapshot stations a second (VERIFIED, desk,
/// `ExportQualityMatrixTests`).
///
/// Now the camera is given **the destination alone** — no departure stop, no
/// crossing — and the departure airport's photographs (already capped at
/// `export.departure_stop_max_photos`) play as a card over the same frozen frame,
/// after the title card and before the camera closes in. The frozen frame is
/// held for the title card plus that stop's own priced hold, so the film's
/// length plan is unchanged: the seconds move from the body into the opening.
///
/// **No pin and no name.** The departure is off this map, so a pin would be a
/// claim about a place that is not where it is drawn; and the departure airport
/// is never named in a type-2 film (ADR 2026-09-05 (c)).
extension LinearTimeline {
    /// The departure's photographs and when they play over the frozen frame.
    struct DepartureCut {
        let stop: RecapTrip.Stop
        let startS: Double
        let endS: Double
    }

    /// What the camera is built from once the frozen-card film is split.
    struct CutPlan {
        let trip: RecapTrip
        let plan: RecapDurationPlan?
        let holds: [Double]
        /// The camera's config: the opening frame held for the card plus the
        /// departure's hold.
        let config: TrackingConfig.Export
        let departure: DepartureCut?
    }

    /// The film's trip, pacing and camera config, with the departure cut out
    /// of the camera's trip when the film is a type-2 film whose flight is not
    /// drawn. Every other film comes back as it went in.
    static func cutPlan(
        _ trip: RecapTrip, untrimmed: RecapTrip, drawsTheFlight: Bool,
        _ config: TrackingConfig.Export, _ pacing: RecapPacing
    ) -> CutPlan {
        let abroad = untrimmed.filmType.hasDestinationAbroad
        let (plan, holds) = Self.pacing(for: trip, config: config, pacing: pacing)
        let unchanged = CutPlan(trip: trip, plan: plan, holds: holds, config: config, departure: nil)
        guard abroad, !drawsTheFlight, let plan, let destination = destination(of: trip),
              let departure = trip.stops.first, let departureHoldS = holds.first else { return unchanged }
        let dropped = trip.stops.count - destination.stops.count
        return CutPlan(
            trip: destination,
            plan: RecapDurationPlan(
                totalS: plan.totalS, openingS: plan.openingS + departureHoldS,
                stopDwellS: Array(plan.stopDwellS.dropFirst(dropped))
            ),
            holds: Array(holds.dropFirst(dropped)),
            config: config.withTitleCardS(config.titleCardS + departureHoldS),
            departure: DepartureCut(
                stop: departure, startS: config.titleCardS, endS: config.titleCardS + departureHoldS
            )
        )
    }

    /// The trip from the destination's first road on: the leading crossings and
    /// every stop before the landing come out. nil — and the film is left as it
    /// was — when the trip does not open on a crossing, or there is no road
    /// after it for a camera to frame.
    private static func destination(of trip: RecapTrip) -> RecapTrip? {
        guard trip.legs.first?.isCrossing == true, trip.stops.count > 1,
              let firstRoad = trip.legs.firstIndex(where: { !$0.isCrossing }),
              let landing = trip.legs[firstRoad].coordinates.first else { return nil }
        let legs = Array(trip.legs[firstRoad...])
        guard RecapTrip.localRouteDistanceM(legs: legs) > 0 else { return nil }
        // The stop the destination's road begins at — nearest its first vertex,
        // as `RecapTypeTwoFilm.destinationJourney` finds the departure.
        let keepFrom = trip.stops.indices.dropFirst().min { lhs, rhs in
            distanceM(trip.stops[lhs].coordinate, landing) < distanceM(trip.stops[rhs].coordinate, landing)
        } ?? 1
        return RecapTrip(
            legs: legs, stops: Array(trip.stops[keepFrom...]), title: trip.title, subtitle: trip.subtitle,
            endCardFigures: trip.endCardFigures, shareURL: trip.shareURL, journeyDates: trip.journeyDates,
            everyLegRoutabilityEstablished: trip.everyLegRoutabilityEstablished
        )
    }

    private static func distanceM(_ lhs: RecapCoordinate, _ rhs: RecapCoordinate) -> Double {
        Geo.distanceM(latA: lhs.lat, lonA: lhs.lon, latB: rhs.lat, lonB: rhs.lon)
    }

    /// The cards over the map at `time`: the boarding pass, and the departure's
    /// photographs over a frozen card.
    func cards(atTime time: Double) -> [OverlayContent] {
        var cards: [OverlayContent] = []
        if let card = journeyCardContent(atTime: time) { cards.append(.journeyCard(card)) }
        if let departure = departureDeck(atTime: time) { cards.append(departure) }
        return cards
    }

    /// Whether the departure's photographs are on screen at `time`.
    func isDepartureCut(atTime time: Double) -> Bool {
        guard let cut = departureCut else { return false }
        return time >= cut.startS && time < cut.endS
    }

    /// The departure's card over the frozen frame — the same deck a stop plays,
    /// on the same envelope, with no pin and no name.
    func departureDeck(atTime time: Double) -> OverlayContent? {
        guard let cut = departureCut, isDepartureCut(atTime: time), !cut.stop.photos.isEmpty else { return nil }
        let window = deckWindow(CameraPath.Hold(stopIndex: -1, startS: cut.startS, endS: cut.endS))
        guard time >= window.start else { return nil }
        let shown = affordablePhotoCount(deck: window, requested: cut.stop.photos.count)
        return .photoDeck(RecapPhotoDeck(
            photos: Array(cut.stop.photos.prefix(shown)),
            focusIndex: focusIndex(atTime: time, deck: window, count: shown),
            reveal: deckReveal(atTime: time, deck: window),
            opacity: deckOpacity(atTime: time, deck: window),
            name: nil, detail: nil, coordinate: nil
        ))
    }
}

extension LinearTimeline {
    /// What a film framed too close or too wide is diagnosed from: the scales
    /// and how many towns set them. Counts and widths, never a place (§0).
    static func announced(_ path: CameraPath, trip: RecapTrip) -> CameraPath {
        let towns = trip.stops.compactMap(\.locality)
        KamomeLog.recap.notice("""
            camera: \(path.areaSpansM.map { String(format: "%.1f", $0 / 1000) }.joined(separator: " / "), privacy: .public) km · \
            \(trip.stops.count) stops · \(towns.count) with a town · \(Set(towns).count) towns
            """)
        return path
    }
}
