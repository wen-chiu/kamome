import Foundation
import KamomeExportEngine
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
    static func journeyDates(_ trip: TripRecord) -> String {
        let started = boardingPassDate(trip.startedAt)
        let ended = boardingPassDate(trip.endedAt ?? trip.startedAt)
        return started == ended ? started : "\(started) – \(ended)"
    }

    /// `15 JUL 2025` — a ticket date.
    ///
    /// **Pinned to `en_US_POSIX`, unlike every other string this file formats.**
    /// A boarding pass is an English artefact and its field labels are English
    /// literals by decision; a date rendered through the device locale would put
    /// one localized token in the middle of that and make two machines render
    /// different frames. The *time zone* stays the device's, because the date a
    /// traveller would recognise is their own local one.
    static func boardingPassDate(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp)).uppercased()
    }
}
