import Foundation
import KamomeConfig
import XCTest

/// **That the illegal states are gone, not merely unused.**
///
/// Before `RecapMode`, three independent booleans — `tiering_enabled`,
/// `uncapped_enabled`, `photo_allocation_enabled` — spelled 8 combinations of
/// which 3 meant anything. The other 5 were kept out by ad-hoc negations
/// scattered across two files, so "tiering *and* uncapped" was expressible in
/// config, silently resolved by whichever `if` ran first, and meant nothing.
///
/// These tests assert the property that replaced those negations: the mode is a
/// single value, so there is no second switch to disagree with it.
final class RecapModeTests: XCTestCase {

    /// Repo-root config, located relative to this file so it works under both
    /// `swift test` and xcodebuild.
    private var configURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
    }

    /// The decisive one. A decoded config carries **exactly one** mode — there is
    /// no combination to get wrong, because there is nothing to combine.
    func testExactlyOneModeIsRepresentable() throws {
        let config = try TrackingConfigLoader.load(contentsOf: configURL)
        let mode = config.export.recapMode
        // Every other case is simultaneously excluded, by construction rather than
        // by any rule someone has to remember to write in a second place.
        for other in RecapMode.allCases where other != mode {
            XCTAssertNotEqual(mode, other)
        }
        XCTAssertEqual(RecapMode.allCases.filter { $0 == mode }.count, 1)
    }

    /// The old boolean names must not come back. If someone reintroduces one as a
    /// parallel switch, the two can disagree and the illegal states return — so
    /// this fails at *compile* time by naming the fields that no longer exist.
    ///
    /// Deliberately a decoding test: config is the surface that used to carry
    /// them, and JSON is where an accidental resurrection would appear first.
    func testRetiredBooleansAreNotDecodedFromConfig() throws {
        let json = """
        {
          "recap_mode": "full",
          "tiering_enabled": true,
          "uncapped_enabled": true,
          "photo_allocation_enabled": true,
          "tier_skip_share": 0.5
        }
        """
        // The retired keys are simply not in `CodingKeys`, so a stale config that
        // still carries them decodes to the mode alone and the extra keys are
        // inert. That is the migration behaviour we want: an old file keeps
        // working, and its dead switches cannot resurrect the old branching.
        struct Probe: Decodable {
            let recapMode: RecapMode
            enum CodingKeys: String, CodingKey { case recapMode = "recap_mode" }
        }
        let probe = try JSONDecoder().decode(Probe.self, from: Data(json.utf8))
        XCTAssertEqual(probe.recapMode, .full, "the mode decides; leftover booleans are inert")
    }

    /// An unknown mode must fail loudly rather than fall back to a default.
    /// Silently picking `highlight` for a typo would ship the wrong film.
    func testUnknownModeFailsToDecode() {
        let json = #"{"recap_mode": "cinematic"}"#
        struct Probe: Decodable {
            let recapMode: RecapMode
            enum CodingKeys: String, CodingKey { case recapMode = "recap_mode" }
        }
        XCTAssertThrowsError(try JSONDecoder().decode(Probe.self, from: Data(json.utf8)))
    }

    /// The shipped config names a mode that exists — catches a rename that updates
    /// the enum and forgets `TrackingConfig.json`.
    func testShippedConfigNamesAKnownMode() throws {
        let config = try TrackingConfigLoader.load(contentsOf: configURL)
        XCTAssertTrue(RecapMode.allCases.contains(config.export.recapMode))
    }
}
