import KamomeConfig
import XCTest

/// The app bundle must ship TrackingConfig.json and load it through the typed
/// loader — the same path KamomeApp takes at launch.
final class AppConfigTests: XCTestCase {
    func testBundledConfigLoads() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "TrackingConfig", withExtension: "json"),
            "TrackingConfig.json missing from app bundle"
        )
        let config = try TrackingConfigLoader.load(contentsOf: url)
        XCTAssertEqual(config.schemaVersion, 1)
    }
}
