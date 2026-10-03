import Foundation
import KamomeConfig
import KamomeRouteMatching

/// **A desk render routes straight to Geoapify, on the desk's own key** (ADR
/// 2026-10-03-desk-renders-route-direct-on-their-own-key).
///
/// Until then every desk harness routed through the shipped Worker and spent the
/// daily ceiling it shares with every user; on 2026-10-02 a day of desk films
/// helped exhaust it and every user's routing failed (#204). The shipped app is
/// unchanged: it still carries no key and still asks the Worker.
///
/// **The key never passes through the environment.** `xcodebuild` echoes every
/// `TEST_RUNNER_` value into its log in clear text, so the key is read here, inside
/// the test process, from `~/.kamome/desk-routing.env` on the Mac — one line, the
/// key alone. A simulator test reads the host's files directly; the host's home is
/// `SIMULATOR_HOST_HOME`, because the process's own home is the simulator's.
///
/// Nothing here ever prints, logs or throws the key. Errors name the file, never
/// its contents.
enum DeskRouting {
    /// The endpoint a desk render routes to when `KAMOME_ROUTING_BASE_URL` is unset.
    static let geoapifyBaseURL = "https://api.geoapify.com"
    /// Relative to the Mac's home directory.
    static let keyFile = ".kamome/desk-routing.env"
    /// The Worker's key, which a desk render must never hold (ADR above).
    static let workerKeyFile = ".kamome/routing.env"

    /// The matching config a desk harness routes with, for the endpoint it was
    /// asked for:
    ///
    /// - `""` routes nothing and reads no key — the offline gates, and CI.
    /// - The shipped Worker is **refused**: a desk render spends no user's quota.
    /// - `api.geoapify.com` carries the desk key.
    /// - Anything else (a local OSRM, a stub) is passed through unkeyed, as before.
    static func matching(
        _ shipped: TrackingConfig.Matching,
        baseURL: String,
        key: () throws -> String = { try DeskRouting.key() }
    ) throws -> TrackingConfig.Matching {
        guard !baseURL.isEmpty else { return shipped.withBaseURL("") }
        let host = Self.host(baseURL)
        if host != nil, host == Self.host(shipped.baseURL) {
            throw HarnessError("""
                KAMOME_ROUTING_BASE_URL names the shipped Worker. Desk renders never route \
                through it — it spends every user's daily ceiling (#204). Unset it to route \
                direct to Geoapify on ~/\(keyFile).
                """)
        }
        guard host == Self.host(geoapifyBaseURL) else { return shipped.withBaseURL(baseURL) }
        return shipped.withAPIKey(try key()).withBaseURL(baseURL)
    }

    /// The live provider a desk render routes with, and one line naming its host —
    /// the host only, since the full URL carries the key.
    static func provider(_ shipped: TrackingConfig.Matching, baseURL: String) throws -> GeoapifyRouteProvider {
        let provider = GeoapifyRouteProvider(config: try matching(shipped, baseURL: baseURL))
        print("KAMOME_DESK_ROUTING endpoint: \(host(baseURL) ?? "(none — routing off)")")
        return provider
    }

    /// The desk key, read from the Mac's `~/.kamome/desk-routing.env`. Refused if
    /// it is the Worker's key: two keys is what keeps the budgets apart.
    static func key(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        guard let home = environment["SIMULATOR_HOST_HOME"], !home.isEmpty else {
            throw HarnessError("SIMULATOR_HOST_HOME is unset — the desk key is read from the Mac's home, on a simulator")
        }
        let root = URL(fileURLWithPath: home)
        let raw: String
        do {
            raw = try String(contentsOf: root.appendingPathComponent(keyFile), encoding: .utf8)
        } catch {
            throw HarnessError("cannot read ~/\(keyFile) on the Mac — the desk routing key lives there (ADR 2026-10-03)")
        }
        let key = try parse(raw)
        if let worker = try? String(contentsOf: root.appendingPathComponent(workerKeyFile), encoding: .utf8),
           worker.split(whereSeparator: \.isNewline).contains(where: { $0.hasSuffix("=\(key)") || $0 == key }) {
            throw HarnessError("~/\(keyFile) holds the Worker's key — the desk needs its own (ADR 2026-10-03)")
        }
        return key
    }

    /// The file holds the key alone, on one line. Anything else is refused rather
    /// than guessed at — and the refusal never quotes what it found.
    static func parse(_ raw: String) throws -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0 == "=" }) else {
            throw HarnessError("~/\(keyFile) must hold the Geoapify key alone, on one line")
        }
        return key
    }

    private static func host(_ url: String) -> String? {
        URL(string: url)?.host?.lowercased()
    }
}
