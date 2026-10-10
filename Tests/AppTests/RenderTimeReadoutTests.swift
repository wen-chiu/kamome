@testable import Kamome
import XCTest

/// **The render time is a Debug readout** (Chiu 2026-10-10, #288: 「Release
/// 隱藏，只留 Debug」). One rule for the finished screen and the film player.
final class RenderTimeReadoutTests: XCTestCase {
    func testAReleaseBuildDrawsNoRenderTime() {
        XCTAssertNil(RenderTimeReadout.text(seconds: 213.5, shown: false))
    }

    func testADebugBuildDrawsItWithOneDecimal() throws {
        let text = try XCTUnwrap(RenderTimeReadout.text(seconds: 213.54, shown: true))
        XCTAssertTrue(text.contains("213.5"), text)
    }

    func testNoMeasuredTimeDrawsNothing() {
        XCTAssertNil(RenderTimeReadout.text(seconds: nil, shown: true))
    }

    /// Test hosts are Debug builds: this pins that the shipped rule keys off
    /// the build configuration, not a setting someone could leave on.
    func testTheRuleIsTheBuildConfiguration() {
        #if DEBUG
        XCTAssertTrue(RenderTimeReadout.isShown)
        #else
        XCTAssertFalse(RenderTimeReadout.isShown)
        #endif
    }
}
