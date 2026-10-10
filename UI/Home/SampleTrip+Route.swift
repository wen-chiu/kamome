import KamomeConfig
import KamomePersistence

extension SampleTrip {
    /// Creates the sample and says where Home should go: **to the trip with
    /// its film playing** (#285), which is what 「先看一支範例影片」 promised.
    ///
    /// A film that cannot be attached does not cost the person the sample: the
    /// trip opens without it, the failure is logged, and 「做成一部影片」 makes one.
    static func createAndRoute(repository: TripRepository, vehicleId: String) throws -> HomeRoute {
        let tripId = try create(repository: repository, vehicleId: vehicleId)
        do {
            try attachFilm(tripId: tripId, repository: repository)
            return .tripPlayingNewestFilm(tripId)
        } catch {
            KamomeLog.storage.error("sample film not attached: \(String(describing: error), privacy: .public)")
            return .trip(tripId)
        }
    }
}
