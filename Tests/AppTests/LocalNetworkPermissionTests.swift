@testable import Kamome
import XCTest

/// **The local-network permission belongs to a Debug build, never to the shipped
/// app** (ADR 2026-09-12 (b)).
///
/// `AppConfig.loadOrDie` refuses a LAN routing endpoint in every non-Debug build.
/// So in the shipped `Info.plist`, `NSLocalNetworkUsageDescription` described to a
/// reviewer a service the app cannot contact, and `NSAllowsLocalNetworking`
/// exempted traffic that cannot exist. Both now come only from the Debug-only
/// post-build phase in `project.yml`.
final class LocalNetworkPermissionTests: XCTestCase {
    func testTheLocalNetworkPermissionExistsOnlyInADebugBuild() throws {
        // The shipped half, at the source: the plist every configuration starts
        // from carries neither key. The artifact half is
        // `Scripts/release/check-archive.sh`, which reads the built plist.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
        let source = try String(contentsOf: root.appendingPathComponent("App/Info.plist"), encoding: .utf8)
        XCTAssertTrue(source.contains("CFBundleDisplayName"), "precondition: App/Info.plist was read")
        XCTAssertFalse(source.contains("NSAllowsLocalNetworking"),
                       "App/Info.plist gives every configuration the ATS local-network exemption")
        XCTAssertFalse(source.contains("NSLocalNetworkUsageDescription"),
                       "App/Info.plist gives every configuration the local-network purpose string")

        // The running half: this test is hosted by the built app, so these are
        // the keys that app actually carries.
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        let allowsLocal = ats?["NSAllowsLocalNetworking"] as? Bool
        let purpose = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String
        #if DEBUG
        // A device build pointed at a LAN endpoint — which the release guard
        // deliberately allows here — must still get past both iOS gates.
        XCTAssertEqual(allowsLocal, true, "the Debug-only build phase did not add NSAllowsLocalNetworking")
        XCTAssertNotNil(purpose, "the Debug-only build phase did not add NSLocalNetworkUsageDescription")
        #else
        XCTAssertNil(allowsLocal, "a non-Debug build carries NSAllowsLocalNetworking")
        XCTAssertNil(purpose, "a non-Debug build carries NSLocalNetworkUsageDescription")
        #endif
    }
}
