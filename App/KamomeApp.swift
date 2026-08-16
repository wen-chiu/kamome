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
        let config: TrackingConfig
        do {
            config = try TrackingConfigLoader.load(contentsOf: url)
        } catch {
            fatalError("TrackingConfig failed to load: \(error)")
        }
        #if !DEBUG
        // A release build is a build that leaves this Mac, and the working-tree
        // `matching.base_url` travels with it. Refusing at launch is the point:
        // the alternative is a TestFlight build that silently stalls on someone
        // else's network, one `timeout_s` per leg, which is exactly what
        // happened on 2026-08-15. Loud here beats dead there.
        guard config.matching.isDistributableEndpoint else {
            fatalError("""
                matching.base_url is "\(config.matching.baseURL)" in a release build. \
                Only "" (matching disabled) or an https endpoint may ship — a LAN address \
                resolves on the developer's Wi-Fi and nowhere else.
                """)
        }
        #endif
        return config
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
