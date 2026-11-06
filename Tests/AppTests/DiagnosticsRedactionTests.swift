@testable import Kamome
import KamomeConfig
import OSLog
import XCTest

/// **What a tester shares holds only the values marked public** (#366, Chiu
/// 2026-11-05). On the iOS 26.5 simulator the system handed `.private` values
/// back in full, and an export's private error text can carry a tile URL — a
/// place (§0). The diagnostics and the kept export history redact every value
/// not marked `.public` themselves, numbers included, so a simulator and a phone
/// write the same file. Every value here is synthetic.
final class DiagnosticsRedactionTests: XCTestCase {
    private struct TileError: Error, CustomStringConvertible {
        let secret: String
        var description: String { "tile https://example.test/tiles/\(secret).pbf could not be read" }
    }

    private struct Probe {
        let secret: String
        let expected: String
    }

    /// One line with each kind of value, and what it must read as once shared.
    private func logProbe() -> Probe {
        let marker = "redaction-probe-\(UUID().uuidString.prefix(8))"
        let secret = "SECRET\(UUID().uuidString.prefix(6))"
        KamomeLog.recap.notice("""
            \(marker, privacy: .public) auto=\(secret) private=\(secret, privacy: .private) \
            error=\(TileError(secret: secret)) count=\(42) kept=\("fixed words", privacy: .public) \
            seconds=\(3.14159, format: .fixed(precision: 1), privacy: .public)s
            """)
        let expected = "\(marker) auto=<private> private=<private> error=<private> count=<private> "
            + "kept=fixed words seconds=3.1s"
        return Probe(secret: secret, expected: expected)
    }

    func testAValueNotMarkedPublicReadsAsPrivateInTheSharedDiagnostics() throws {
        let probe = logProbe()

        let url = try XCTUnwrap(DiagnosticsLog.export())
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains(probe.expected), "the probe line is missing or not redacted as expected")
        XCTAssertFalse(text.contains(probe.secret), "a value not marked public reached the shared diagnostics")
    }

    func testTheKeptExportHistoryHoldsTheSameLineRedacted() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("redaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.txt")
        // A second early: a line logged just after `Date.now` can read back
        // dated a fraction of a millisecond before it (VERIFIED, simulator).
        let start = Date.now.addingTimeInterval(-1)
        let probe = logProbe()

        // Awaited, not polled: on a CI runner the log-store read outlasted a
        // 15 s wait (PR #373's first run).
        await ExportLogHistory.keep(since: start, keptExports: 3, file: file)?.value
        guard FileManager.default.fileExists(atPath: file.path) else {
            return XCTFail("the history was not written; `export log history:` in the storage log says why")
        }
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains(probe.expected), "the probe line is missing or not redacted as expected")
        XCTAssertFalse(text.contains(probe.secret), "a value not marked public reached the kept export history")
    }

    /// The file written before #366 held the system's rendering: it is deleted
    /// and never shared.
    func testTheHistoryWrittenBeforeRedactionIsDeletedUnread() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("redaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent(ExportLogHistory.legacyFileName)
        try "\(ExportLogHistory.blockMark)old\nSECRET in full\n".write(to: legacy, atomically: true, encoding: .utf8)

        XCTAssertNil(ExportLogHistory.read(file: folder.appendingPathComponent("history.txt")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "the unredacted history survived")
    }

    /// A public value loses nothing: a line whose values are all public reads
    /// back exactly as the system rendered it, precision included.
    func testALineWhoseValuesAreAllPublicReadsAsTheSystemWroteIt() throws {
        let marker = "redaction-parity-\(UUID().uuidString.prefix(8))"
        let start = Date.now.addingTimeInterval(-1)
        KamomeLog.recap.notice("""
            \(marker, privacy: .public) 100% · \(4242, privacy: .public) frames · \
            \(Int32(-7), privacy: .public) · \(UInt(9), privacy: .public) · \(true, privacy: .public) · \
            \(212.45, format: .fixed(precision: 1), privacy: .public)s · \
            \(0.0371, format: .fixed(precision: 2), privacy: .public)s · \
            \(9.5, format: .fixed(precision: 0), privacy: .public)\(-2.75, format: .fixed(precision: 1), privacy: .public)\
            \(3, privacy: .public) · \(2.5, privacy: .public) · \("50% off", privacy: .public)
            """)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(date: start), matching: NSPredicate(format: "subsystem == %@", KamomeLog.subsystem)
        )
        let log = try XCTUnwrap(
            entries.lazy.compactMap { $0 as? OSLogEntryLog }.first { $0.composedMessage.hasPrefix(marker) }
        )
        XCTAssertEqual(LogRedaction.message(log), log.composedMessage)
    }

    // MARK: - The rule, without a log store

    private func piece(_ literal: String, _ placeholder: String, _ value: LogRedaction.Piece.Value)
        -> LogRedaction.Piece {
        LogRedaction.Piece(literal: literal, placeholder: placeholder, value: value)
    }

    func testOnlyAPlaceholderNamedPublicKeepsItsValue() {
        let pieces = [
            piece("a=", "%{public}s", .string("kept")),
            piece(" b=", "%s", .string("SECRET")),
            piece(" c=", "%{private}s", .string("SECRET")),
            piece(" d=", "%ld", .signed(7)),
            piece(" e=", "%{private,mask.hash}s", .string("SECRET")),
            piece(" f=", "%{public,sensitive}s", .string("SECRET")),
            piece(" g=", "%{bool,public}d", .signed(1)),
            piece(" 100%% done", "", .unreadable)
        ]
        XCTAssertEqual(
            LogRedaction.rebuild(format: "", pieces: pieces, composed: ""),
            "a=kept b=<private> c=<private> d=<private> e=<private> f=<private> g=true 100% done"
        )
    }

    /// The precision is read off the system's text, but the text written is the
    /// public number's own: beside a private value, a match cannot borrow from it.
    func testAPublicNumbersPrecisionNeverCarriesAPrivateValue() {
        let pieces = [
            piece("x=", "%s", .string("123.45")),
            piece("", "%{public}.*f", .double(9.0)),
            piece("s", "", .unreadable)
        ]
        XCTAssertEqual(LogRedaction.rebuild(format: "", pieces: pieces, composed: "x=123.459s"), "x=<private>9s")
        XCTAssertEqual(LogRedaction.rebuild(format: "", pieces: pieces, composed: "x=<private>9.00s"), "x=<private>9.00s")
    }

    /// No rendering of the number in the system's text: six decimals, the C
    /// default, rather than a guess.
    func testAnUnrecoverablePrecisionFallsBackToTheDefault() {
        let pieces = [piece("t=", "%{public}.*f", .double(2.75)), piece("s", "", .unreadable)]
        XCTAssertEqual(LogRedaction.rebuild(format: "", pieces: pieces, composed: "something else"), "t=2.750000s")
    }

    func testAMessageWithNoPiecesShowsOnlyItsFormatString() {
        XCTAssertEqual(LogRedaction.rebuild(format: "a %{public}s b", pieces: [], composed: "a SECRET b"), "a %{public}s b")
    }
}
