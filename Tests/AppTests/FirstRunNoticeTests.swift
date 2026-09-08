@testable import Kamome
import KamomeConfig
import XCTest

/// **The one-time telling** (Chiu 2026-09-04; ADR 2026-09-05 (b)): the user is told
/// once, on first run, that real trip coordinates leave this device — and is not
/// told again.
///
/// Two of these assertions are the whole point of the design and are worth
/// naming, because a passing suite is not what makes them true:
///
/// - **Silence while nothing leaves.** The shipped config has `base_url` `""`,
///   so a notice shown today would describe a state that has not arrived —
///   `Docs/release-readiness.md` S3b is the standing example of what that costs.
/// - **The version, not a Bool.** The wording is still Chiu's to rule on, so the
///   stored fact has to be able to say *which* notice was acknowledged.
final class FirstRunNoticeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "kamome.tests.firstRun.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// The endpoint is the *effective* one, so this is also what a build with no
    /// API key gets — `AppConfig.applyingRoutingKey` empties `base_url` for it,
    /// and a build that cannot route has nothing to disclose.
    func testNothingIsSaidWhileNothingLeavesTheDevice() {
        XCTAssertFalse(
            FirstRunNotice.shouldPresent(matching: matching(baseURL: ""), defaults: defaults),
            "routing is off, so the notice would be describing a state that has not arrived"
        )
    }

    /// The config flip is what publishes the notice: the same defaults that were
    /// silent above must speak the moment an endpoint exists.
    func testTheFlipIsWhatPublishesTheNotice() {
        XCTAssertTrue(
            FirstRunNotice.shouldPresent(matching: matching(baseURL: worker), defaults: defaults),
            "an endpoint exists, so this build can send and the user has not been told"
        )
    }

    func testTheNoticeIsShownOnceAndThenRemembered() {
        let live = matching(baseURL: worker)
        XCTAssertTrue(FirstRunNotice.shouldPresent(matching: live, defaults: defaults))
        FirstRunNotice.acknowledge(defaults: defaults)
        XCTAssertFalse(
            FirstRunNotice.shouldPresent(matching: live, defaults: defaults),
            "told once means told once"
        )
    }

    /// What a reinstall does, stated as a test rather than left as folklore:
    /// `UserDefaults` goes with the app, so the notice comes back. Over-telling
    /// is the safe direction and this pins which direction was chosen.
    func testAnEmptyDefaultsStoreIsTold() {
        FirstRunNotice.acknowledge(defaults: defaults)
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertTrue(
            FirstRunNotice.shouldPresent(matching: matching(baseURL: worker), defaults: defaults),
            "a reinstall loses the acknowledgement, and the user is told again"
        )
    }

    /// Acknowledging notice *n* must not silence notice *n+1*. This is the test
    /// that fails the day someone materially changes what is sent, or where it
    /// goes, without raising `FirstRunNotice.version`.
    func testAMateriallyNewNoticeIsShownAgain() {
        defaults.set(FirstRunNotice.version - 1, forKey: "kamome.privacyNoticeAcknowledgedVersion")
        XCTAssertTrue(
            FirstRunNotice.shouldPresent(matching: matching(baseURL: worker), defaults: defaults),
            "an older notice was acknowledged, not this one"
        )
    }

    /// `api_key_required` **is** the topology, so the sentence follows it rather
    /// than being maintained alongside it: the flip changes the flag, and the
    /// copy that names Kamome's relay arrives with it.
    func testTheHopSentenceFollowsWhereTheKeyLives() {
        XCTAssertEqual(
            PrivacyNoticeCopy.hopKey(for: matching(baseURL: geoapify, apiKeyRequired: true)),
            "privacy_hop_direct",
            "this build carries the key and calls the provider itself"
        )
        XCTAssertEqual(
            PrivacyNoticeCopy.hopKey(for: matching(baseURL: worker, apiKeyRequired: false)),
            "privacy_hop_relay",
            "the key lives in the relay, which is a party the notice has to name"
        )
    }

    /// One formatter for both surfaces (`AboutView` and `FirstRunNoticeView`).
    /// The failure this forbids is not a crash: it is the two screens printing
    /// different numbers for the same fact, which no other test would see.
    func testBothSurfacesFormatTheImportedSentenceIdentically() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "TrackingConfig", withExtension: "json"))
        let shipped = try TrackingConfigLoader.load(contentsOf: url).matching
        let rendered = PrivacyNoticeCopy.importedBody(for: shipped)

        XCTAssertFalse(rendered.contains("%"), "an unfilled specifier reached the screen: \(rendered)")
        XCTAssertTrue(rendered.contains("250"), "the thinning distance: \(rendered)")
        XCTAssertTrue(rendered.contains("100"), "the per-leg cap: \(rendered)")
    }

    // MARK: - Helpers

    private let worker = "https://kamome-routing.example.workers.dev"
    private let geoapify = "https://api.geoapify.com"

    private func matching(baseURL: String, apiKeyRequired: Bool = false) -> TrackingConfig.Matching {
        TrackingConfig.Matching(
            baseURL: baseURL,
            chunkSize: 100,
            confidenceMin: 0.5,
            radiusM: 25,
            timeoutS: 10,
            tripBudgetS: 120,
            displayEpsilonM: 5,
            routeMaxDetourRatio: 2.5,
            routeWaypointMinSpacingM: 250,
            routeWaypointRadiusM: 500,
            apiKeyRequired: apiKeyRequired
        )
    }
}
