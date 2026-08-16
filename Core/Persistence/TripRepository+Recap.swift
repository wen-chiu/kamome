import Foundation
import GRDB

/// Recap-facing writes, split out of `TripRepository` for the same reason
/// `TripRepository+Import.swift` was: the type has a size budget, and these
/// belong to a different question than recording a trip does.
extension TripRepository {
    /// Which subject this trip's recap draws (schema v3). Passing nil clears the
    /// choice, which readers see as the catalogue default.
    ///
    /// A column rather than a render-time argument because it is a fact about
    /// the trip: changing subject must never require re-importing, and the
    /// export path composes from the database.
    public func setTripVehicle(tripId: String, vehicleId: String?) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE trip SET vehicle = ? WHERE id = ?",
                arguments: [vehicleId, tripId]
            )
        }
    }
}
