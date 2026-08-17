import Foundation
import KamomeExportEngine

/// Remembers which subject the user last chose, so the next trip opens on it.
///
/// **Read when a trip is created, not when one is rendered.** The trip's own row
/// then says what it draws, and changing the default later cannot silently
/// restyle a film someone already made. A trip whose column is NULL predates the
/// choice entirely and reads as the car — that is a different fact from "chose
/// the car", and the two stay distinguishable in the data.
enum LastVehicleChoice {
    private static let key = "kamome.lastVehicleId"

    /// What a newly created trip should start as. Falls back to the catalogue
    /// default, and refuses a remembered id that no longer exists — a set can be
    /// deleted between one trip and the next.
    static func forNewTrip(defaults: UserDefaults = .standard) -> String {
        guard let stored = defaults.string(forKey: key),
              VehicleCatalog.subject(id: stored) != nil
        else { return VehicleCatalog.defaultSubjectId }
        return stored
    }

    static func remember(_ vehicleId: String, defaults: UserDefaults = .standard) {
        defaults.set(vehicleId, forKey: key)
    }
}
