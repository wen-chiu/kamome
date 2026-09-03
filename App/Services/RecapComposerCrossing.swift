import Foundation
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer

/// **What a crossing does to the copy** — split out of `RecapComposer` on
/// 2026-09-03 for file length, and because these three are one decision rather
/// than three helpers.
///
/// The 2026-09-02 review settled two things about a type-2 film's text:
///
/// - **every kilometre a viewer reads is the local journey**, so the flight comes
///   off `stats.distanceM` before either card prints it;
/// - the **Journey Card** prints the last photograph's date before the flight and
///   the first after it.
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
    static func localDistanceM(stats: TripStats?, legs: [RecapTrip.Leg]) -> Double? {
        guard let stats else { return nil }
        let flown = legs.filter(\.isCrossing).reduce(0.0) { total, leg in
            total + zip(leg.coordinates, leg.coordinates.dropFirst()).reduce(0.0) { run, pair in
                // The **same** function the Journey Card measures the flight with
                // (`LinearTimeline.crossingDistanceM`). These are two halves of
                // one figure — what comes off the odometer and what the pass
                // prints — and computing them two ways is how they drift.
                run + Geo.greatCircleM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
            }
        }
        return max(stats.distanceM - flown, 0)
    }

    /// The two dates the Journey Card prints: **the last photograph taken before
    /// the flight and the first taken after it** (Chiu 2026-09-02).
    ///
    /// Composed here because this is the only layer that has both `taken_at` and a
    /// formatter — `PhotoRef` is a pointer and `RecapTrip.Stop` carries only a
    /// `dayLabel` string, and neither the timeline nor the renderer may go looking
    /// for a date.
    ///
    /// **Split by the crossing's own ends, using the same "nearest stop" rule
    /// `RecapTypeTwoFilm` uses to pick the departure**, so the card and the film
    /// cannot disagree about which stop the flight leaves from. nil whenever
    /// either side has no dated photograph — a real answer the card honours.
    static func crossingDates(
        legs: [RecapTrip.Leg], stops: [StopRecord], photos: [PhotoRefRecord]
    ) -> RecapTrip.CrossingDates? {
        guard let crossing = legs.first(where: \.isCrossing),
              let origin = crossing.coordinates.first, let arrival = crossing.coordinates.last,
              let departureStop = nearestStop(to: origin, in: stops),
              let arrivalStop = nearestStop(to: arrival, in: stops) else { return nil }
        let taken = { (stopId: String) in
            photos.filter { $0.stopId == stopId }.compactMap(\.takenAt)
        }
        guard let left = taken(departureStop.id).max(), let landed = taken(arrivalStop.id).min() else {
            return nil
        }
        return RecapTrip.CrossingDates(
            departure: boardingPassDate(left), arrival: boardingPassDate(landed)
        )
    }

    private static func nearestStop(to point: RecapCoordinate, in stops: [StopRecord]) -> StopRecord? {
        stops.min {
            PhotoImportClusterer.haversineMeters(point.lat, point.lon, $0.lat, $0.lon)
                < PhotoImportClusterer.haversineMeters(point.lat, point.lon, $1.lat, $1.lon)
        }
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
