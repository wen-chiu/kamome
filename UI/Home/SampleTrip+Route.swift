import KamomeConfig
import KamomePersistence

extension SampleTrip {
    /// Creates the sample and says where Home should go: **to the trip with
    /// its film playing** (#285), which is what 「先看一支範例影片」 promised.
    ///
    /// With no film for the app's language, or one that cannot be attached, the
    /// trip opens without it and 「製作旅程影片」 makes one. Only the second is a
    /// fault, and only it is logged as one.
    static func createAndRoute(repository: TripRepository, vehicleId: String) throws -> HomeRoute {
        let tripId = try create(repository: repository, vehicleId: vehicleId)
        do {
            try attachFilm(tripId: tripId, repository: repository)
            return .tripPlayingNewestFilm(tripId)
        } catch FilmFailure.noFilmForLanguage {
            KamomeLog.storage.notice("sample opened without a film: none ships in this language")
            return .trip(tripId)
        } catch {
            KamomeLog.storage.error("sample film not attached: \(String(describing: error), privacy: .public)")
            return .trip(tripId)
        }
    }
}
