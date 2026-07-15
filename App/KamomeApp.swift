import KamomeConfig
import KamomePersistence
import SwiftUI

@main
struct KamomeApp: App {
    /// Loaded once at startup; a broken or incomplete config must crash the
    /// launch with a message naming the problem (spec §0 rule 2).
    private static let trackingConfig = AppConfig.loadOrDie()

    @State private var session: TrackingSession

    init() {
        let database = AppConfig.openDatabaseOrDie()
        let repository = TripRepository(database: database)
        #if DEBUG
        DemoSeeder.seedIfRequested(repository: repository)
        #endif
        _session = State(initialValue: TrackingSession(
            config: Self.trackingConfig,
            repository: repository
        ))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(session)
        }
    }
}

enum AppConfig {
    static func loadOrDie() -> TrackingConfig {
        guard let url = Bundle.main.url(forResource: "TrackingConfig", withExtension: "json") else {
            fatalError("TrackingConfig.json is missing from the app bundle")
        }
        do {
            return try TrackingConfigLoader.load(contentsOf: url)
        } catch {
            fatalError("TrackingConfig failed to load: \(error)")
        }
    }

    static func openDatabaseOrDie() -> AppDatabase {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return try AppDatabase.onDisk(path: support.appendingPathComponent("kamome.sqlite").path)
        } catch {
            fatalError("Kamome database failed to open: \(error)")
        }
    }
}
