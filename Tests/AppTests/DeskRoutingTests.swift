@testable import Kamome
import KamomeConfig
import XCTest

/// Desk renders route direct to Geoapify on their own key, never through the
/// Worker (ADR 2026-10-03-desk-renders-route-direct-on-their-own-key, #204).
///
/// No assertion here ever prints the real key: the file test checks its shape
/// and compares it, and the rest use a stand-in.
final class DeskRoutingTests: XCTestCase {
    private let shipped = { () -> TrackingConfig.Matching in
        // swiftlint:disable:next force_try
        try! AppConfig.loadOrDie().matching
    }()

    private func noKeyRead() throws -> String {
        XCTFail("this endpoint must not read the desk key")
        return ""
    }

    /// The offline gates — and CI, which has no key — route nothing and never
    /// touch the key file.
    func testRoutingOffReadsNoKey() throws {
        let matching = try DeskRouting.matching(shipped, baseURL: "", key: noKeyRead)
        XCTAssertEqual(matching.baseURL, "")
        XCTAssertEqual(matching.apiKey, "")
    }

    /// The point of the ADR: a desk render never spends the users' ceiling.
    func testTheShippedWorkerIsRefused() throws {
        XCTAssertFalse(shipped.baseURL.isEmpty, "precondition: the app ships the Worker URL")
        XCTAssertThrowsError(try DeskRouting.matching(shipped, baseURL: shipped.baseURL, key: noKeyRead))
        XCTAssertThrowsError(
            try DeskRouting.matching(shipped, baseURL: shipped.baseURL.uppercased(), key: noKeyRead),
            "the host compare is case-insensitive"
        )
    }

    func testGeoapifyCarriesTheDeskKey() throws {
        let matching = try DeskRouting.matching(shipped, baseURL: DeskRouting.geoapifyBaseURL) { "desk-stand-in" }
        XCTAssertEqual(matching.baseURL, DeskRouting.geoapifyBaseURL)
        XCTAssertEqual(matching.apiKey, "desk-stand-in")
        XCTAssertEqual(matching.timeoutS, shipped.timeoutS, "every other tunable is the shipped one")
    }

    /// A local OSRM or a stub gets positions as it always did, and no key.
    func testAnotherEndpointIsPassedThroughUnkeyed() throws {
        let matching = try DeskRouting.matching(shipped, baseURL: "https://routing.invalid", key: noKeyRead)
        XCTAssertEqual(matching.baseURL, "https://routing.invalid")
        XCTAssertEqual(matching.apiKey, "")
    }

    func testTheKeyFileHoldsTheKeyAlone() throws {
        XCTAssertEqual(try DeskRouting.parse("abc123\n"), "abc123")
        XCTAssertEqual(try DeskRouting.parse("  abc123  "), "abc123")
        XCTAssertThrowsError(try DeskRouting.parse(""))
        XCTAssertThrowsError(try DeskRouting.parse("\n"))
        XCTAssertThrowsError(try DeskRouting.parse("GEOAPIFY_API_KEY=abc123"), "the Worker file's shape")
        XCTAssertThrowsError(try DeskRouting.parse("abc123\ndef456"))
    }

    func testNoHostHomeIsRefused() {
        XCTAssertThrowsError(try DeskRouting.key(environment: [:]))
    }

    /// **The proof that a simulator test can read the Mac's file**: on a Mac with
    /// the desk key this reads it through `SIMULATOR_HOST_HOME`, and confirms it is
    /// key-shaped and not the Worker's (`key()` refuses that). CI has no key file,
    /// and says so rather than passing.
    func testTheDeskKeyIsReadableFromTheSimulator() throws {
        let home = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
            "the test process runs on a simulator, which names the Mac's home"
        )
        let file = URL(fileURLWithPath: home).appendingPathComponent(DeskRouting.keyFile)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: file.path),
            "no desk key on this machine (CI) — ~/\(DeskRouting.keyFile) is Chiu's desk only"
        )
        let key = try DeskRouting.key()
        XCTAssertTrue(
            key.wholeMatch(of: #/[0-9a-f]{32}/#) != nil,
            "the desk key is not shaped like a Geoapify key (32 hex characters)"
        )
    }
}
