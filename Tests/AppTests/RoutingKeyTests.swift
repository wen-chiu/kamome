@testable import Kamome
import KamomeConfig
import XCTest

/// **The app carries no routing key, and no build can give it one** (ADR
/// 2026-09-12).
///
/// Until then a key arrived through a gitignored `Config/Secrets.xcconfig` →
/// `Config/Base.xcconfig` → `Info.plist` → `Bundle.main`. The config flip (ADR
/// 2026-09-08) pointed the app at the Worker, which holds the key; removing the
/// path is what made "no key in the app" true on every machine, rather than only
/// on the ones that happened to have no secrets file.
///
/// Two halves: the rule for an endpoint that still needs a key (routing off, never
/// a request that can only be refused), and the absence of any way for a key to
/// arrive — in the committed build inputs and in the built bundle itself.
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
    ///
    /// ⚠️ **The premise is stated here rather than inherited from the shipped
    /// file** (2026-09-08, the config flip). This test used to take
    /// `api_key_required` from `TrackingConfig.json`, which was `true`; the flip
    /// made it `false`, and a test that reads its own premise out of a file the
    /// product may change is a test that stops holding its rule the day the file
    /// moves. The rule is unchanged: **an endpoint that needs a key routes
    /// nothing without one.**
    func testNoKeyDisablesRoutingRatherThanFailing() throws {
        let config = try shipped().withMatching(
            try directMatching().withBaseURL("https://routing.example.com")
        )
        let resolved = AppConfig.routingForAKeylessBuild(config)

        XCTAssertEqual(resolved.matching.baseURL, "", "no key must mean routing disabled")
        XCTAssertEqual(resolved.matching.apiKey, "")
        // Every other tunable still comes from the config it was given.
        XCTAssertEqual(resolved.matching.timeoutS, config.matching.timeoutS)
        XCTAssertEqual(resolved.export, config.export)
    }

    /// A config that already has routing off is left alone rather than "disabled
    /// twice".
    ///
    /// ⚠️ Until 2026-09-08 this asserted *the shipped config* was the disabled
    /// one. The flip pointed it at the Worker, so that precondition is now false
    /// by decision — but the rule it was testing is about an already-disabled
    /// config, not about what ships, so it is restated with one rather than
    /// deleted.
    func testNoKeyLeavesAnAlreadyDisabledConfigAlone() throws {
        let config = try shipped().withMatching(try shipped().matching.withBaseURL(""))
        XCTAssertEqual(config.matching.baseURL, "", "precondition: this config has routing off")
        XCTAssertEqual(AppConfig.routingForAKeylessBuild(config), config)
    }

    /// 🔴 **The config flip itself, as a gate** (Chiu 2026-09-05, ADR 2026-09-08).
    ///
    /// The three tests around this one are about the *rule*; this one is about
    /// **what Kamome actually ships**, and it is the one that goes red if anyone
    /// reverts the flip or half-reverts it. Both values matter and they only work
    /// as a pair: the Worker URL without `api_key_required: false` would route
    /// nothing, and `false` without the URL would leave routing off.
    func testTheShippedConfigPointsAtTheWorkerAndNeedsNoKey() throws {
        let config = try shipped()

        XCTAssertEqual(config.matching.baseURL, "https://kamome-routing.kamome-site.workers.dev",
                       "the app must call the Worker, which is the only thing holding a key")
        XCTAssertFalse(config.matching.apiKeyRequired,
                       "the app carries no key, so requiring one would switch routing off in the shipped build")
        XCTAssertEqual(config.matching.apiKey, "", "and the committed file can never supply one")

        // The whole point of the pair: a build with no key routes anyway.
        XCTAssertEqual(AppConfig.routingForAKeylessBuild(config), config,
                       "a keyless build must reach the Worker unchanged — that is what the flip bought")
    }

    /// 🔴 **The built app has no key to carry** (2026-09-12, the build path removed).
    ///
    /// Restated from `testAKeyIsCarriedOnMatchingAndNotFromTheFile`, whose subject
    /// — a key read out of the bundle and put on `matching` — no longer exists:
    /// there is no `Info.plist` field to read one from. That test protected "the
    /// only key the app sends is one the build deliberately supplied"; the
    /// strongest form of that is now "the build supplies none". The other half —
    /// `withAPIKey` carries a key without enabling an endpoint — is Core's, and
    /// `ConfigLoaderTests` holds it.
    ///
    /// This runs inside the host app, so `Bundle.main` is the built `Kamome.app`:
    /// exactly where a machine-local `Config/Secrets.xcconfig` used to land. An
    /// **empty** field fails too — that is the mapping come back on a machine that
    /// happens to have no key.
    func testTheBuiltAppCarriesNoRoutingKeyField() {
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "KamomeRoutingAPIKey"),
            "Info.plist must not define KamomeRoutingAPIKey at all — the key has no build path"
        )
        XCTAssertEqual(AppConfig.loadOrDie().matching.apiKey, "", "and the config the app loads carries no key")
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

        let resolved = AppConfig.routingForAKeylessBuild(try shipped().withMatching(worker))

        XCTAssertEqual(resolved.matching.baseURL, "https://kamome-routing.example.workers.dev",
                       "the Worker endpoint survives a keyless build")
        XCTAssertEqual(resolved.matching.apiKey, "", "and the app still carries no key")
    }

    /// The same config with the flag left true — a build pointed straight at the
    /// provider — still routes nothing rather than sending coordinates that can
    /// only come back 401 (§0: exposure for nothing).
    func testAnEndpointThatNeedsAKeyStillRoutesNothingWithoutOne() throws {
        let direct = try directMatching()
        XCTAssertTrue(direct.apiKeyRequired, "precondition: this endpoint expects to supply a key")

        let resolved = AppConfig.routingForAKeylessBuild(try shipped().withMatching(direct))

        XCTAssertEqual(resolved.matching.baseURL, "")
    }

    /// The direct-to-provider block — the shape Kamome shipped in before the
    /// 2026-09-08 flip — decoded the way the app would read it. It is written
    /// out here, rather than taken from `TrackingConfig.json`, precisely so the
    /// rules above keep holding after the file stops having this shape.
    private func directMatching() throws -> TrackingConfig.Matching {
        let json = """
        {"base_url":"https://api.geoapify.com","chunk_size":100,"confidence_min":0.5,
         "radius_m":25,"timeout_s":10,"trip_budget_s":60,"display_epsilon_m":5,
         "route_max_detour_ratio":2.5,"route_waypoint_min_spacing_m":250,
         "route_waypoint_radius_m":500,"api_key_required":true}
        """
        return try JSONDecoder().decode(TrackingConfig.Matching.self, from: Data(json.utf8))
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

    /// **No committed build input maps the key into the app** (2026-09-12).
    ///
    /// Restated from `testUnsetAndPlaceholderValuesCountAsNoKey`, which classified
    /// the shapes an `Info.plist` value took when a build had no key — empty, the
    /// template placeholder, the unexpanded `$(…)`. Those shapes existed only
    /// because the field did; with the field gone there is no value to classify,
    /// and `usableRoutingKey` went with it. The rule underneath — a machine must
    /// not be able to put a key into the app by having one lying around — is held
    /// here one step earlier, where it cannot depend on which machine built: the
    /// two files that generate the bundle's `Info.plist` never name the setting.
    /// Comment lines are excluded so the history can still be explained in place.
    func testNoBuildInputMapsTheRoutingKey() throws {
        for path in ["project.yml", "App/Info.plist"] {
            let text = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            let live = text.split(whereSeparator: \.isNewline)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            XCTAssertFalse(live.isEmpty, "precondition: \(path) was read")
            XCTAssertFalse(live.contains { $0.contains("KamomeRoutingAPIKey") },
                           "\(path) maps a routing key into Info.plist")
            XCTAssertFalse(live.contains { $0.contains("KAMOME_ROUTING_API_KEY") },
                           "\(path) expands the routing key build setting")
        }
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

        // In a worktree — now the recommended setup for parallel sessions —
        // .git is a file whose `gitdir:` line points at the real git dir, and
        // the index lives there, not under repoRoot/.git. Resolve both shapes
        // so the guard runs in a worktree instead of silently skipping.
        let indexURL = Self.gitIndexURL(repoRoot: repoRoot)
        guard let indexURL, let indexData = try? Data(contentsOf: indexURL) else {
            throw XCTSkip("git index not readable (no .git?) — the CI step covers this check")
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
            // prefix of a longer tracked path
            let afterNeedle = range.upperBound
            if afterNeedle < indexData.endIndex && indexData[afterNeedle] == nul {
                XCTFail("Config/Secrets.xcconfig is tracked by git — it must be in .gitignore")
                return
            }
            searchStart = range.upperBound
        }
        // Not found in the index — correct.
    }

    /// The git index for this checkout, whether `.git` is a directory (a normal
    /// clone → `.git/index`) or a file (a worktree → a `gitdir:` pointer whose
    /// target holds the index). Returns nil only when there is no `.git` at all,
    /// e.g. a source export — the one case the test legitimately skips.
    private static func gitIndexURL(repoRoot: URL) -> URL? {
        let dotGit = repoRoot.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGit.appendingPathComponent("index")
        }
        // A worktree's `.git` is `gitdir: <path>` on one line. The path may be
        // absolute (what `git worktree add` writes) or relative to repoRoot.
        guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        let prefix = "gitdir:"
        guard let line = pointer.split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let target = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        let gitDir = target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : repoRoot.appendingPathComponent(target).standardizedFileURL
        return gitDir.appendingPathComponent("index")
    }

    /// This checkout's root, for the tests that read committed files.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// **No committed config file puts a key into a build** (2026-09-12).
    ///
    /// Restated from `testTheExampleFileContainsNoUsableKey`. The template it read,
    /// `Config/Secrets.xcconfig.example`, was deleted with the build path: it
    /// documented how to create a file no build reads any more, and a committed
    /// template is an instruction to do exactly that. What it guarded — a key
    /// reaching a build from a file in `Config/` — is held here over every
    /// xcconfig in the directory, including any template someone re-adds.
    ///
    /// `Config/Secrets.xcconfig` itself is skipped by name: it is gitignored, may
    /// still exist on a machine that built before this change, and is its owner's
    /// file. `testTheSecretsFileIsNotTracked` is what keeps it out of git.
    func testNoConfigFileDefinesOrIncludesTheRoutingKey() throws {
        let config = repoRoot.appendingPathComponent("Config")
        let names = try FileManager.default.contentsOfDirectory(atPath: config.path)
        XCTAssertTrue(names.contains("Base.xcconfig"), "precondition: the scan found the app's xcconfig")

        for name in names where name.contains(".xcconfig") && name != "Secrets.xcconfig" {
            let text = try String(contentsOf: config.appendingPathComponent(name), encoding: .utf8)
            let live = text.split(whereSeparator: \.isNewline)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            XCTAssertFalse(live.contains { $0.contains("KAMOME_ROUTING_API_KEY") },
                           "Config/\(name) defines the routing key build setting")
            XCTAssertFalse(live.contains { $0.contains("Secrets.xcconfig") },
                           "Config/\(name) includes the gitignored secrets file")
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
