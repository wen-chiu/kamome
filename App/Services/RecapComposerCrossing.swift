import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer

/// **What a crossing does to the copy** — split out of `RecapComposer` on
/// 2026-09-03 for file length, and because these three are one decision rather
/// than three helpers.
///
/// Two rules about a type-2 film's text:
///
/// - **every kilometre a viewer reads is the local journey** (2026-09-02), so the
///   flight comes off `stats.distanceM` before either card prints it;
/// - the **Journey Card** prints the **trip's** date range (2026-09-04, replacing
///   the crossing's own two dates — see `journeyDates`).
///
/// Both live in the app layer for the same reason all the other copy does: this
/// is the only place with both the stored records and a formatter, and
/// localization never enters `KamomeExportEngine`.
extension RecapComposer {
    /// **The trip's distance with the flown legs taken out** — what every card in
    /// the film reports (Chiu 2026-09-02).
    ///
    /// `TripStats.distanceM` sums the trackpoints, and on an imported trip those
    /// include the crossing: `auckland-crossing` measures 9,024 km, of which
    /// 8,755 km is a flight. The flight is not deleted from the film — it appears
    /// once, on the Journey Card, labelled as the flight.
    ///
    /// **Subtracted from `stats.distanceM` rather than recomputed from the legs.**
    /// The recorded distance stays the base and only the flight comes off it;
    /// re-deriving the whole figure from display geometry would quietly change
    /// what the number *is* — simplified, snapped display polyline rather than
    /// what was travelled — while looking like the same fix.
    ///
    /// 🔴 **`Geo.distanceM`, and it must stay `Geo.distanceM`** — the
    /// equirectangular one, even though the Journey Card prints the flight with
    /// `Geo.greatCircleM`. `TripStats.compute` builds `distanceM` by summing
    /// `Geo.distanceM` over the trackpoints, so **that is the measure this total
    /// is in**, and subtracting a great-circle flight from an equirectangular
    /// total mixes two rulers. Measured 2026-09-03 on `auckland-crossing`: doing
    /// so puts **148 km** on both cards where the journey is **269 km**.
    ///
    /// The pass is a different question and gets the other answer, deliberately:
    /// it *prints a distance*, so it owes the true geodesic (`greatCircleM`,
    /// 8,876 km here); this *removes a contribution from a total*, so it owes the
    /// measure that total was built with (8,755 km here). Same flight, two rulers,
    /// each used where it is correct. **Nothing in the film shows both**, so a
    /// viewer is never handed two numbers that fail to add up.
    static func localDistanceM(stats: TripStats?, legs: [RecapTrip.Leg]) -> Double? {
        guard let stats else { return nil }
        let flown = legs.filter(\.isCrossing).reduce(0.0) { total, leg in
            total + zip(leg.coordinates, leg.coordinates.dropFirst()).reduce(0.0) { run, pair in
                run + Geo.distanceM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
            }
        }
        return max(stats.distanceM - flown, 0)
    }

    /// **The records a film is made from: the trip without its flight home**
    /// (ADR 2026-09-01, built 2026-09-23).
    ///
    /// The rule is `RecapTypeTwoFilm.homecomingLegIndex`; this only applies it to
    /// the stored records, because this is the layer that has their **times**.
    /// Everything from the first leg of the flight home onward is dropped, and so
    /// is every stop the traveller reached after that leg began. The destination's
    /// own last stop — in practice the airport they left from — is kept: it is
    /// where the film ends.
    ///
    /// **Cut by time, not by nearest stop.** A round trip returns to the place it
    /// left, so "the stop nearest the homecoming" is exactly the question that
    /// has two answers on a round trip. The segments and stops share one clock,
    /// and a stop is after the homecoming when it was reached after it began.
    ///
    /// Before classification, deliberately: the flight home is a return to
    /// ground the trip already covered, which `RecapFilmType` folds anyway — and
    /// when that ground is one airport photograph at each end, the two points do
    /// not share a bounding box, so only removing the return counts the trip
    /// right. Everything downstream — the type, the camera, the card's figures —
    /// then reads one journey.
    ///
    /// Returns the input unchanged when the trip does not come home, which is
    /// every local trip and every one-way trip.
    static func filmRecords(
        segments: [(segment: SegmentRecord, points: [TrackpointRecord])],
        stops: [StopRecord],
        epsilonM: Double,
        matchedEpsilonM: Double,
        homeRadiusM: Double
    ) -> (segments: [(segment: SegmentRecord, points: [TrackpointRecord])], stops: [StopRecord]) {
        // One leg per segment, with the segment it came from: `legs(from:)`
        // drops degenerate segments, so leg and segment indices can differ.
        let indexed = segments.indices.compactMap { index -> (segment: Int, leg: RecapTrip.Leg)? in
            legs(from: [segments[index]], epsilonM: epsilonM, matchedEpsilonM: matchedEpsilonM)
                .first.map { (index, $0) }
        }
        guard let homecoming = RecapTypeTwoFilm.homecomingLegIndex(
            legs: indexed.map(\.leg), homeRadiusM: homeRadiusM
        ) else { return (segments, stops) }
        let firstDropped = indexed[homecoming].segment
        let leftAt = segments[firstDropped].segment.startedAt
        return (Array(segments[..<firstDropped]), stops.filter { $0.arrivedAt <= leftAt })
    }

    /// **The date range the boarding pass prints: the whole trip's** (Chiu
    /// 2026-09-04, from the film).
    ///
    /// 🔴 **This replaced a decided field, and the semantics moved with it.**
    /// Until 2026-09-04 the pass printed the *crossing's* two dates — the last
    /// photograph before the flight and the first after it (Chiu 2026-09-02) —
    /// and that pipeline is deleted rather than left dormant. A ticket's DATE row
    /// now reads the **journey's** start and end, from `trip.startedAt` /
    /// `endedAt`, which is what `titleSubtitle` has always used.
    ///
    /// ⚠️ **Honest, and a semantic shift worth naming.** A boarding pass is an
    /// object about a flight, and this row is now about the trip the flight is
    /// part of. That was the instruction; if a render reads as though the card is
    /// claiming *flight* dates, the answer is a label change and it is Chiu's,
    /// not an implementer's.
    ///
    /// Collapses to one date when the trip begins and ends on the same day: a
    /// range with the same value twice reads as a bug.
    static func journeyDates(_ trip: TripRecord, clock: TripClock = .uniform()) -> String {
        let endedAt = trip.endedAt ?? trip.startedAt
        let started = boardingPassDate(trip.startedAt, zone: clock.zone(at: trip.startedAt))
        let ended = boardingPassDate(endedAt, zone: clock.zone(at: endedAt))
        return started == ended ? started : "\(started) – \(ended)"
    }

    /// `15 JUL 2025` — a ticket date.
    ///
    /// **Pinned to `en_US_POSIX`, unlike every other string this file formats.**
    /// A boarding pass is an English artefact and its field labels are English
    /// literals by decision; a date rendered through the device locale would put
    /// one localized token in the middle of that and make two machines render
    /// different frames. The *time zone* is where the moment happened
    /// (`TripClock`, arch review 2026-09-26) — the date a traveller would
    /// recognise is the local one there, not whatever zone the phone is in now.
    static func boardingPassDate(_ timestamp: Double, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp)).uppercased()
    }

    /// **The closing card's three figures: how far, how long, how many places**
    /// (Chiu 2026-09-05, in that order, from his layout).
    ///
    /// It was one sentence — `N stops · M days · K km` — and before that two lines
    /// with driving hours. The card now sets a row of three columns, so what
    /// crosses the narrow waist is **(value, label) pairs**: the renderer draws
    /// them and never splits a string it did not write.
    ///
    /// Both halves are finished here because this is the only layer with a locale.
    /// The label is uppercased **by the catalog**, never by `.uppercased()`, which
    /// follows the *device's* locale and would turn a Turkish `i` into `İ` in a
    /// frame nobody reviewed.
    ///
    /// ⚠️ **The inflection is a two-key `one` / everything-else split, and that is
    /// a real limitation.** A String Catalog plural variation is the right tool
    /// and the compiler refuses it here — *"Plural variation requires referencing
    /// the number in the string"* — because the number is drawn as its own figure
    /// and never appears in the label. Xcode's own remedy is separate top-level
    /// strings, which is what these are. It is correct for English and for
    /// zh-Hant (one category, both keys the same word); **a language with a `few`
    /// or `many` category cannot be served by it**, and the answer then is to put
    /// the count back in the label rather than to add a third key here.
    ///
    /// 🔴 **Every input is a fact about the film, and none of them needs
    /// `TripStats`.** That matters more than it looks: an **imported** trip has no
    /// `TripStats` at all — `ImportService` writes no `stats_json`, only
    /// `TrackingSession` and `DemoSeeder` do — so the old `guard let stats`
    /// returned `[]` and the closing card of every imported film was **empty**
    /// (measured 2026-09-05 on all three review fixtures). Sourcing the figures
    /// from the journey the film drew is what puts a card back on screen.
    /// The same gap still empties the title card's subtitle: `HANDOFF.md`.
    ///
    /// - `distanceM` — `RecapTrip.localRouteDistanceM`, the odometer's own axis,
    ///   grouped by `RecapOverlayRenderer.grouped` so the card and the HUD set one
    ///   number one way.
    /// - days — `trip.startedAt`…`endedAt`, counted exactly as the HUD's `Day N`
    ///   counts, so the film cannot say "3 DAYS" over a frame reading `Day 4`.
    /// - `stopCount` — the stops of the film's own journey (`filmJourney`).
    static func endCardFigures(
        trip: TripRecord, distanceM: Double, stopCount: Int, clock: TripClock = .uniform()
    ) -> [RecapEndCardFigure] {
        let days = dayCount(trip: trip, clock: clock)
        return [
            RecapEndCardFigure(
                value: RecapOverlayRenderer.grouped(Int((distanceM / 1000).rounded())),
                label: String(localized: "recap_figure_label_km")
            ),
            RecapEndCardFigure(
                value: RecapOverlayRenderer.grouped(days),
                label: days == 1
                    ? String(localized: "recap_figure_label_day")
                    : String(localized: "recap_figure_label_days")
            ),
            RecapEndCardFigure(
                value: RecapOverlayRenderer.grouped(stopCount),
                label: stopCount == 1
                    ? String(localized: "recap_figure_label_stop")
                    : String(localized: "recap_figure_label_stops")
            )
        ]
    }

    /// How many days the trip covered, by the **same arithmetic as the HUD's day
    /// chip** (`dayLabel`): calendar dates, both ends counted (`TripDay`). Two
    /// day counters on one film that disagree by one is worse than either answer.
    static func dayCount(trip: TripRecord, clock: TripClock) -> Int {
        clock.dayCount(startedAt: trip.startedAt, endedAt: trip.endedAt ?? trip.startedAt)
    }

    /// Every moment counted in one calendar's zone — a trip with no stop zones.
    static func dayCount(trip: TripRecord, calendar: Calendar = .current) -> Int {
        dayCount(trip: trip, clock: .uniform(calendar.timeZone))
    }

    /// **The journey the film tells** — the whole trip, or, when the film opens on
    /// a flight, only its destination half (`RecapTypeTwoFilm`).
    ///
    /// 🔴 **This asks `RecapTypeTwoFilm` rather than deciding.** The trim runs
    /// inside `LinearTimeline`, *after* this function has already worded the
    /// closing card, so the card had been counting a journey the film does not
    /// show: on `auckland-crossing` it claimed 6 stops where the film visits 5,
    /// the extra being Taipei's, which the trim drops (measured 2026-09-05).
    /// Re-implementing "which stops survive" here would fix the number and keep
    /// the defect — two rules that have to be corrected twice.
    ///
    /// The film type is classified from the **untrimmed** legs, as
    /// `LinearTimeline` classifies it, because the trim leaves one local journey
    /// and a trimmed trip reads honestly as a local one.
    static func filmJourney(
        legs: [RecapTrip.Leg], stops: [RecapTrip.Stop], config: TrackingConfig.Export?,
        everyLegRoutabilityEstablished: Bool
    ) -> (legs: [RecapTrip.Leg], stops: [RecapTrip.Stop]) {
        let filmType = RecapFilmType.classify(
            legs: legs, everyLegEstablished: everyLegRoutabilityEstablished
        )
        guard filmType.hasDestinationAbroad, let config,
              let journey = RecapTypeTwoFilm.destinationJourney(
                  legs: legs, stops: stops, config: config
              )
        else { return (legs, stops) }
        return journey
    }
}
