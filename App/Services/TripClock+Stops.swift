import Foundation
import KamomeImportKit
import KamomePersistence

extension TripClock {
    /// The clock a stored trip's days are counted by: each stop's geocoded zone
    /// (`stop.time_zone`, schema v14). Stops never asked, or asked with no zone
    /// ("") add nothing; with none at all it is the phone's zone, as before.
    init(stops: [StopRecord], fallback: TimeZone = .current) {
        self.init(zones: stops.compactMap { stop in
            guard let identifier = stop.timeZone, !identifier.isEmpty,
                  let zone = TimeZone(identifier: identifier) else { return nil }
            return StopZone(arrivedAt: stop.arrivedAt, departedAt: stop.departedAt, zone: zone)
        }, fallback: fallback)
    }
}
