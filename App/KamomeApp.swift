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
        return routingForAKeylessBuild(config)
    }

    /// **The app carries no routing key, from any source** (ADR 2026-09-12).
    ///
    /// Until then a key could reach the bundle from a gitignored
    /// `Config/Secrets.xcconfig`, through an `Info.plist` field this enum read
    /// back out. The config flip (ADR 2026-09-08) made that key unnecessary — the
    /// Worker holds it — but not unreachable: on a machine that still had the
    /// file, every request to the Worker carried the real key in its query string,
    /// and every archive built there carried it in `Info.plist`. The field, the
    /// include and the bundle read are gone, so there is nothing left to read.
    ///
    /// **What remains is the rule for an endpoint that needs a key, and it still
    /// matters.** Routing off is an existing, designed state — `matching.base_url`
    /// empty, legs keep raw geometry and draw dashed (PD-2), with user-facing copy
    /// already written for it — so such an endpoint degrades into that state
    /// rather than inventing a new failure.
    ///
    /// **`api_key_required` is what keeps the rule from switching the Worker off**
    /// (2026-08-20). The Worker holds the key and the app is *supposed* to carry
    /// none, so an unconditional "no key ⇒ routing off" would disable routing in
    /// exactly the configuration Kamome ships. Deleting the rule instead would be
    /// worse: a build pointed straight at Geoapify would put real coordinates in
    /// the query string of every request only to be refused — §0 exposure buying
    /// nothing.
    ///
    /// Pure, so the rule is testable without a bundle.
    static func routingForAKeylessBuild(_ config: TrackingConfig) -> TrackingConfig {
        guard config.matching.apiKeyRequired, !config.matching.baseURL.isEmpty else { return config }
        KamomeLog.routing.notice(
            "routing disabled — this endpoint needs an API key and the app carries none, so every leg stays raw (PD-2)"
        )
        return config.withMatching(config.matching.withBaseURL(""))
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
