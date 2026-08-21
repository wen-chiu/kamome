@testable import Kamome
import KamomeConfig
import XCTest

/// **How the routing key reaches the app, and what happens when it does not.**
///
/// The key must not enter git, so it arrives through a gitignored
/// `Config/Secrets.xcconfig` → `Config/Base.xcconfig` → `Info.plist` →
/// `Bundle.main`. These cover the decision that path feeds, which is the half
/// that can be tested without a bundle.
///
/// The case that matters most is the one that will break for the next person and
/// not for whoever added this: **a checkout with no secrets file at all.**
final class RoutingKeyTests: XCTestCase {
    private func shipped() throws -> TrackingConfig {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url)
    }

    /// A build with no key routes nothing — and does not crash doing it.
    func testNoKeyDisablesRoutingRatherThanFailing() throws {
        let config = try shipped().withMatching(
            try shipped().matching.withBaseURL("https://routing.example.com")
        )
        let resolved = AppConfig.applyingRoutingKey(config, key: nil)

        XCTAssertEqual(resolved.matching.baseURL, "", "no key must mean routing disabled")
        XCTAssertEqual(resolved.matching.apiKey, "")
        // Every other tunable still comes from the file.
        XCTAssertEqual(resolved.matching.timeoutS, config.matching.timeoutS)
        XCTAssertEqual(resolved.export, config.export)
    }

    /// The shipped config already ships routing disabled, so a keyless build is
    /// unchanged rather than "disabled twice".
    func testNoKeyLeavesAnAlreadyDisabledConfigAlone() throws {
        let config = try shipped()
        XCTAssertEqual(config.matching.baseURL, "", "precondition: the committed config ships routing off")
        XCTAssertEqual(AppConfig.applyingRoutingKey(config, key: nil), config)
    }

    /// A key present is carried on `matching`, never read from the config file.
    func testAKeyIsCarriedOnMatchingAndNotFromTheFile() throws {
        let config = try shipped()
        let resolved = AppConfig.applyingRoutingKey(config, key: "abc123")

        XCTAssertEqual(resolved.matching.apiKey, "abc123")
        XCTAssertEqual(resolved.matching.baseURL, config.matching.baseURL, "a key does not enable an endpoint")
    }

    /// `TrackingConfig.json` is committed and bundled, so the key must not be
    /// decodable from it even if someone adds the field by hand.
    func testTheConfigFileCannotSupplyAKey() throws {
        let json = """
        {"base_url":"https://routing.example.com","chunk_size":100,"confidence_min":0.5,
         "radius_m":25,"timeout_s":10,"trip_budget_s":60,"display_epsilon_m":5,
         "route_max_detour_ratio":2.5,"route_waypoint_min_spacing_m":250,
         "route_waypoint_radius_m":500,"api_key_required":true,"api_key":"leaked-into-git"}
        """
        let matching = try JSONDecoder().decode(TrackingConfig.Matching.self, from: Data(json.utf8))
        XCTAssertEqual(matching.apiKey, "", "a key in the committed file must be ignored, not honoured")
    }

    /// **The Cloudflare Worker's shape** (`Docs/pre-launch.md`): the key lives in
    /// the Worker, the app carries none, and routing must stay **on**. Without
    /// `api_key_required` this is the configuration Kamome ships in — and the
    /// unconditional "no key ⇒ routing off" rule would have silently disabled
    /// routing in it.
    func testAnEndpointThatHoldsItsOwnKeyRoutesWithoutOne() throws {
        let worker = try workerMatching()
        XCTAssertFalse(worker.apiKeyRequired, "precondition")

        let resolved = AppConfig.applyingRoutingKey(try shipped().withMatching(worker), key: nil)

        XCTAssertEqual(resolved.matching.baseURL, "https://kamome-routing.example.workers.dev",
                       "the Worker endpoint survives a keyless build")
        XCTAssertEqual(resolved.matching.apiKey, "", "and the app still carries no key")
    }

    /// The same config with the flag left true — a build pointed straight at the
    /// provider — still routes nothing rather than sending coordinates that can
    /// only come back 401 (§0: exposure for nothing).
    func testAnEndpointThatNeedsAKeyStillRoutesNothingWithoutOne() throws {
        let direct = try shipped().matching.withBaseURL("https://api.geoapify.com")
        XCTAssertTrue(direct.apiKeyRequired, "precondition: the shipped config expects to supply a key")

        let resolved = AppConfig.applyingRoutingKey(try shipped().withMatching(direct), key: nil)

        XCTAssertEqual(resolved.matching.baseURL, "")
    }

    /// The Worker-shaped block, decoded the way the app would read it, so the
    /// test exercises the config file rather than a hand-built struct.
    private func workerMatching() throws -> TrackingConfig.Matching {
        let json = """
        {"base_url":"https://kamome-routing.example.workers.dev","chunk_size":100,"confidence_min":0.5,
         "radius_m":25,"timeout_s":10,"trip_budget_s":60,"display_epsilon_m":5,
         "route_max_detour_ratio":2.5,"route_waypoint_min_spacing_m":250,
         "route_waypoint_radius_m":500,"api_key_required":false}
        """
        return try JSONDecoder().decode(TrackingConfig.Matching.self, from: Data(json.utf8))
    }

    /// The three ways a build legitimately has no key. The `$(…)` case is the
    /// no-`Secrets.xcconfig` build whose plist kept its placeholder.
    func testUnsetAndPlaceholderValuesCountAsNoKey() {
        XCTAssertNil(AppConfig.usableRoutingKey(""))
        XCTAssertNil(AppConfig.usableRoutingKey("   "))
        XCTAssertNil(AppConfig.usableRoutingKey("$(KAMOME_ROUTING_API_KEY)"))
        XCTAssertNil(AppConfig.usableRoutingKey("replace-me-with-the-routing-provider-key"))
        XCTAssertEqual(AppConfig.usableRoutingKey("  abc123  "), "abc123")
    }

    /// **The secrets file must never be tracked.** A gitignore rule is
    /// convention; this test is enforcement. It reads the git index directly
    /// — `Process` is not available on iOS, but the index is a binary file
    /// we can scan for the path string.
    func testTheSecretsFileIsNotTracked() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root

        let indexURL = repoRoot.appendingPathComponent(".git/index")
        // In CI or worktrees .git may be a file pointing elsewhere; if the
        // index is not readable, the CI step catches it instead — skip
        // rather than false-pass.
        guard let indexData = try? Data(contentsOf: indexURL) else {
            throw XCTSkip("git index not readable — the CI step covers this check")
        }

        // The git index stores each tracked path as a NUL-terminated string.
        // Scanning for the path bytes is sound because a false positive would
        // require another tracked path containing this one as a substring,
        // which cannot happen (it would be a directory conflict).
        let needle = Data("Config/Secrets.xcconfig".utf8)
        let nul = UInt8(0)
        var searchStart = indexData.startIndex
        while let range = indexData.range(of: needle, in: searchStart..<indexData.endIndex) {
            // Check it is NUL-terminated (a real index entry) and not a
            // prefix of "Config/Secrets.xcconfig.example"
            let afterNeedle = range.upperBound
            if afterNeedle < indexData.endIndex && indexData[afterNeedle] == nul {
                XCTFail("Config/Secrets.xcconfig is tracked by git — it must be in .gitignore")
                return
            }
            searchStart = range.upperBound
        }
        // Not found in the index — correct.
    }

    /// The committed example file must not contain a usable key. If someone
    /// pastes a real key into the example and commits it, this fails.
    func testTheExampleFileContainsNoUsableKey() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let example = repoRoot.appendingPathComponent("Config/Secrets.xcconfig.example")
        let content = try String(contentsOf: example, encoding: .utf8)

        // Extract any value assigned to KAMOME_ROUTING_API_KEY
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("KAMOME_ROUTING_API_KEY"),
                  let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let value = String(trimmed[trimmed.index(after: eqIdx)...])
                .trimmingCharacters(in: .whitespaces)
            XCTAssertNil(
                AppConfig.usableRoutingKey(value),
                "Secrets.xcconfig.example contains a usable key — it must hold only the placeholder"
            )
        }
    }

    /// The release guard is untouched by any of this: a provider host and a
    /// future Worker URL both satisfy it, and a LAN address still does not.
    func testTheReleaseGuardStillRefusesACleartextLANEndpoint() throws {
        let matching = try shipped().matching
        XCTAssertTrue(matching.withBaseURL("").isDistributableEndpoint)
        XCTAssertTrue(matching.withBaseURL("https://api.geoapify.com").isDistributableEndpoint)
        XCTAssertTrue(matching.withBaseURL("https://kamome.example.workers.dev").isDistributableEndpoint)
        XCTAssertFalse(matching.withBaseURL("http://192.168.50.179:5100").isDistributableEndpoint)
        // A key does not launder an endpoint the guard refuses.
        XCTAssertFalse(
            matching.withBaseURL("http://192.168.50.179:5100").withAPIKey("abc").isDistributableEndpoint
        )
    }
}
