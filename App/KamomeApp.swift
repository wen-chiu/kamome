import KamomeConfig
import SwiftUI

@main
struct KamomeApp: App {
    /// Loaded once at startup; a broken or incomplete config must crash the
    /// launch with a message naming the problem (spec §0 rule 2).
    let trackingConfig = AppConfig.loadOrDie()

    var body: some Scene {
        WindowGroup {
            // Phase 0 placeholder proving the String Catalog pipeline.
            // S1 Home replaces this in Phase 1.
            Text("start_journey")
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
}
