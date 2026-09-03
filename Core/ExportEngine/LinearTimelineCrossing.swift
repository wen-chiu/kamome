import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **What the crossing beat puts on screen, and what it takes off** — split out
/// of `LinearTimeline` on 2026-09-03, the same way `LinearTimelinePacing` and
/// `LinearTimelineStopScene` were, and for the same two reasons: the file was at
/// its 400-line budget, and this is a coherent slice rather than an arbitrary
/// half.
///
/// Two halves of one beat:
///
/// - the **Journey Card**, a boarding pass naming both ends, on screen for the
///   crossing and nowhere else (Chiu 2026-09-02);
/// - the **trail reveal**, which is where the crossing's dashed leg is put away
///   once the aircraft lands and drawn again for the end card.
///
/// `routeCoordinates` and `legRanges` became `internal` for this file, exactly as
/// `LegRange` itself did on 2026-09-02: Swift scopes `private` to the file, so a
/// split that keeps the reveal with the beat it belongs to has to widen them.
/// Nothing outside `KamomeExportEngine` can see either.
extension LinearTimeline {
    // MARK: - The boarding pass

    /// The card's **invariant half**, resolved once when the timeline is built:
    /// the two regions, the flight's distance, and the dates. `progress` and
    /// `opacity` are placeholders here and are replaced every frame by
    /// `journeyCardContent(atTime:)` — the card is one object whose two
    /// time-varying fields the beat drives.
    ///
    /// nil, and **no card is drawn**, when `CountryExtent` cannot name an end.
    /// The table has six rows and returns nil outside them (both shipping
    /// fixtures, TW→NZ and TW→JP, resolve). There is no honest region name to
    /// print in that case and a boarding pass with a blank FROM is worse than no
    /// boarding pass, so the beat simply carries the sprite as it did before.
    ///
    /// ⚠️ The log line names **which end** failed and nothing else — never a
    /// coordinate, never a place (`CLAUDE.md` §0).
    static func journeyCard(trip: RecapTrip, locale: Locale) -> RecapJourneyCard? {
        guard let ends = RecapTypeTwoFilm.crossingEnds(trip) else { return nil }
        let origin = CountryExtent.containing(lat: ends.origin.lat, lon: ends.origin.lon)
        let destination = CountryExtent.containing(lat: ends.destination.lat, lon: ends.destination.lon)
        guard let from = region(origin, locale: locale), let to = region(destination, locale: locale) else {
            KamomeLog.recap.notice("""
                journey card: no country extent covers the \
                \(origin == nil ? "origin" : "destination") end of the crossing — \
                drawing no card
                """)
            return nil
        }
        return RecapJourneyCard(
            from: from, to: to, distanceM: crossingDistanceM(trip),
            dates: trip.crossingDates, progress: 0, opacity: 0
        )
    }

    /// One end's two names. **English first — a boarding pass is an English
    /// artefact** — with the viewer's own language beneath it, and nil when the
    /// system cannot name the country at all.
    private static func region(_ country: CountryExtent.Country?, locale: Locale) -> RecapJourneyCard.Region? {
        guard let country, let english = country.localizedName(locale: Locale(identifier: "en_US")) else {
            return nil
        }
        return RecapJourneyCard.Region(
            english: english.uppercased(), local: country.localizedName(locale: locale)
        )
    }

    /// The flight's length, along the crossing leg's own polyline.
    ///
    /// **The one flown number in the film.** Everything else a viewer reads —
    /// the HUD odometer, the title card's subtitle, the end card's stats — counts
    /// the local journey (Chiu 2026-09-02), which is why this one is labelled as
    /// the flight where it is drawn.
    ///
    /// 🔴 **`greatCircleM`, not `Geo.distanceM`** (2026-09-03). The camera's whole
    /// distance axis is equirectangular, which is right for it and wrong here: on
    /// this fixture's Taipei → Auckland diagonal the flat-earth figure is **121 km
    /// short**, and this number is *printed on something shaped like a document*.
    /// It also has to agree with `RecapComposer.localDistanceM`, which subtracts
    /// the same flight from the trip's recorded distance with a haversine — two
    /// halves of one figure, computed two ways, is how they drift.
    private static func crossingDistanceM(_ trip: RecapTrip) -> Double {
        trip.legs.filter(\.isCrossing).reduce(0.0) { total, leg in
            total + zip(leg.coordinates, leg.coordinates.dropFirst()).reduce(0.0) { run, pair in
                run + Geo.greatCircleM(
                    latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon
                )
            }
        }
    }

    /// The card at `time`, or nil outside the crossing beat.
    ///
    /// **The beat, not the arc.** The arc runs `zoom_transition_s` past the
    /// landing while the camera closes into the destination; the pass belongs to
    /// the stretch the aircraft is actually in the air for.
    ///
    /// `progress` is smoothstepped over the beat with **the same easing the
    /// subject moves under** (`CameraPath.state`), so the aircraft printed on the
    /// card and the sprite on the map travel together rather than drifting apart.
    func journeyCardContent(atTime time: Double) -> RecapJourneyCard? {
        guard let card = journeyCard, let beat = path.crossingBeatWindowsS.first,
              time >= beat.lowerBound, time <= beat.upperBound else { return nil }
        let span = max(beat.upperBound - beat.lowerBound, 1e-6)
        let elapsed = time - beat.lowerBound
        // Never more than half the beat each side, so a beat shorter than two
        // ramps still reaches full opacity instead of fading straight back out.
        let fade = max(min(cardFadeS, span / 2), 1e-6)
        return RecapJourneyCard(
            from: card.from, to: card.to, distanceM: card.distanceM, dates: card.dates,
            progress: Self.smoothstep(elapsed / span),
            opacity: min(Self.smoothstep(elapsed / fade), Self.smoothstep((span - elapsed) / fade))
        )
    }

    // MARK: - Here, and there

    /// **A Kamome mark on each end of the flight**, over the opening's still
    /// frame only (Chiu 2026-09-04).
    ///
    /// The closeout's handover item 1 — *"the wide flight frame loses the
    /// viewer"* — taking its **second** candidate answer: draw Kamome's own marks
    /// at the two ends rather than lowering `crossing_flight_max_longitude_deg`.
    /// The threshold stays 70.
    ///
    /// **From t=0 until the aircraft lands**, which is the Journey Card's window
    /// extended forward to the head of the film. No beat is added and no second
    /// is spent: the opening's first 6.59 s is already one held frame, and what
    /// was missing was something on it, not time.
    ///
    /// Gated on `opensOnTheFlight` and having two ends — deliberately **not** on
    /// the card's `CountryExtent` condition. A mark needs no country name, so a
    /// trip whose ends fall outside the table draws no pass and still draws its
    /// marks.
    ///
    /// ⚠️ **The origin yields to the departure stop's pin.** They are the same
    /// point — the airport the flight leaves from — so drawing both would put two
    /// marks on one place. Exactly one is ever returned: while any stop is
    /// holding, the stop's own pin is the mark, and this one is nil.
    func flightEnds(atTime time: Double) -> OverlayContent? {
        guard opensOnTheFlight, let ends = flightEndCoordinates,
              let beat = path.crossingBeatWindowsS.first, time <= beat.upperBound else { return nil }
        // Full strength for the whole opening, easing out as the arc begins to
        // close — the same ramp the pass leaves on, so the two go together.
        let fade = max(min(cardFadeS, beat.upperBound - beat.lowerBound), 1e-6)
        let opacity = Self.smoothstep((beat.upperBound - time) / fade)
        guard opacity > 0.001 else { return nil }
        return .flightEnds(
            origin: holdingStop(atTime: time) == nil ? ends.origin : nil,
            destination: ends.destination,
            opacity: opacity
        )
    }

    // MARK: - The trail, and the dash the crossing puts away

    /// The revealed trail, cut back into legs (typed-leg pass 2026-07-26). The
    /// camera reveals along one continuous distance axis; this maps the cut back
    /// onto the leg ranges so a reconstructed motorway and an inferred straight
    /// line reach the renderer as separate strokes with separate stories.
    ///
    /// The leg the head is inside gets the interpolated head point appended, so
    /// the trail still ends exactly under the vehicle rather than at the last
    /// whole vertex.
    ///
    /// **The crossing's dash is put away once the aircraft lands, and comes back
    /// for the end card** (Chiu 2026-09-02) — see `crossingIsPutAway`.
    func revealedLegs(atTime time: Double) -> [RecapRouteLeg] {
        let cut = path.revealCut(atTime: time)
        let head = RecapCoordinate(lat: cut.head.lat, lon: cut.head.lon)
        let putAway = crossingIsPutAway(atTime: time)
        var revealed: [RecapRouteLeg] = []

        let travelledM = path.traveledDistanceM(atTime: time)
        for leg in legRanges {
            guard cut.vertexCount > leg.range.lowerBound else { break }
            if leg.isCrossing, putAway, hasLanded(leg, travelledM: travelledM) { continue }
            let end = min(cut.vertexCount, leg.range.upperBound)
            var coordinates = Array(routeCoordinates[leg.range.lowerBound..<end])
            if cut.vertexCount < leg.range.upperBound { coordinates.append(head) }
            guard coordinates.count >= 2 else { continue }
            revealed.append(RecapRouteLeg(
                coordinates: coordinates, mode: leg.mode, provenance: leg.provenance
            ))
        }
        return revealed
    }

    /// Whether the reveal has reached the far end of `leg`.
    ///
    /// **Distance, not vertex count.** The obvious test — "the reveal has passed
    /// the last vertex" — is off by one at exactly the moment that matters: the
    /// arrival stop's hold is anchored *at* the crossing's end distance, so while
    /// it plays the head sits on the last vertex without passing it and the dash
    /// stayed on screen for the whole first stop of the destination. Measured
    /// 2026-09-03; the assertion in `RecapJourneyCardTests` is what caught it.
    ///
    /// `>=` against the leg's own end distance is exact at the landing and false
    /// for every instant of the crossing, with no k-th-crossing-to-k-th-beat
    /// mapping to drift out of step.
    private func hasLanded(_ leg: LegRange, travelledM: Double) -> Bool {
        let last = leg.range.upperBound - 1
        guard path.cumulativeM.indices.contains(last) else { return false }
        return travelledM >= path.cumulativeM[last]
    }

    /// Whether a landed crossing's dashed leg is hidden right now.
    ///
    /// **From the landing until the end card** (Chiu 2026-09-02). On the Auckland
    /// film the dash was drawn for the remaining 42 seconds — a straight line
    /// across the Pacific stretching out of frame behind a road trip in New
    /// Zealand, saying nothing after the second it landed. It is drawn again for
    /// the end card, where the whole journey is what is being shown.
    ///
    /// ⚠️ **The redrawn dash runs off the frame edge, and that is expected rather
    /// than a bug to fix here.** The end reveal was refitted on 2026-09-02 to the
    /// *destination's local journey*, because a frame holding the whole route is
    /// unexpressible and killed the Auckland render (`Docs/handoff-type2-films.md`
    /// §5). Re-widening the end reveal to bracket both countries is the defect,
    /// not the remedy — put the frame in front of the designer instead.
    private func crossingIsPutAway(atTime time: Double) -> Bool {
        time < durationS - endCardS
    }
}
