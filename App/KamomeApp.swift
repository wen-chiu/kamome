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
        return applyingRoutingKey(config, key: routingAPIKeyFromBundle())
    }

    /// The key as the bundle carries it, or nil when this build has none.
    ///
    /// Delivered by `Config/Secrets.xcconfig` (gitignored) through
    /// `Config/Base.xcconfig` into an `Info.plist` entry, so the key reaches the
    /// app without ever being a source file. `Base.xcconfig` defines the setting
    /// as empty by default, which is why a checkout with no secrets file still
    /// builds and simply arrives here with nothing.
    static func routingAPIKeyFromBundle() -> String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "KamomeRoutingAPIKey") as? String
        return raw.flatMap(usableRoutingKey)
    }

    /// Three ways a build legitimately has no key, all of them normal:
    /// the setting was empty (no `Secrets.xcconfig`), the template was copied but
    /// never edited, or the setting was never defined at all and the plist kept
    /// its literal `$(…)` placeholder.
    static func usableRoutingKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !key.hasPrefix("replace-me"),
              !key.contains("$(") else { return nil }
        return key
    }

    /// **A missing key disables routing; it never crashes.**
    ///
    /// Routing off is an existing, designed state — `matching.base_url` empty,
    /// legs keep raw geometry and draw dashed (PD-2), with user-facing copy
    /// already written for it. So a build with no key degrades into that state
    /// rather than inventing a new failure, and a fresh checkout or CI run is
    /// unaffected.
    ///
    /// Pure and separate from the bundle read so the decision itself is testable
    /// without an `Info.plist`.
    static func applyingRoutingKey(_ config: TrackingConfig, key: String?) -> TrackingConfig {
        guard let key else {
            guard !config.matching.baseURL.isEmpty else { return config }
            KamomeLog.routing.notice(
                "routing disabled — this build carries no API key, so every leg stays raw (PD-2)"
            )
            return config.withMatching(config.matching.withBaseURL(""))
        }
        return config.withMatching(config.matching.withAPIKey(key))
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
