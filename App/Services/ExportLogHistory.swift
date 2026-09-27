import Foundation
import KamomeConfig
import OSLog

/// **Where one export's wall-clock went, stage by stage** (Chiu 2026-09-27).
///
/// `render cost` prices the drawing, and only for a film that finished. The
/// stages before it — routing, composing, downloading iCloud photographs — can
/// be most of a slow export and were never timed. One line on every exit:
///
///     export stages: roads 4.1s · compose 0.3s · photos 38.0s · drawing 212.4s · total 254.8s · finished
///
/// A stage that never started is absent, so a line ending at `compose` says the
/// export stopped there. Durations and fixed words only (§0).
@MainActor
final class ExportStageClock {
    let startedAt = Date.now
    private let started = ContinuousClock.now
    private var current: (name: String, since: ContinuousClock.Instant)?
    private var finished: [(name: String, seconds: Double)] = []

    /// Closes the stage in progress, if any, and opens `name`.
    func enter(_ name: String) {
        close()
        current = (name, .now)
    }

    func report(outcome: RecapExportOutcome) {
        close()
        let stages = finished.map { String(format: "%@ %.1fs", $0.name, $0.seconds) }
        let total = Self.seconds(ContinuousClock.now - started)
        let line = (stages + [String(format: "total %.1fs", total), Self.name(outcome)]).joined(separator: " · ")
        KamomeLog.recap.notice("export stages: \(line, privacy: .public)")
    }

    private func close() {
        guard let current else { return }
        finished.append((current.name, Self.seconds(ContinuousClock.now - current.since)))
        self.current = nil
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// The outcome's name only — a failure's message stays in its own line.
    private static func name(_ outcome: RecapExportOutcome) -> String {
        switch outcome {
        case .finished: return "finished"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }
}

/// **Each export's own log lines, kept past the launch that wrote them**
/// (Chiu 2026-09-27: testers' logs are how export time gets analysed).
///
/// `DiagnosticsLog` reads the unified log, which an app can only read for its
/// own current process — so a tester who rendered a film, closed Kamome and
/// shared diagnostics the next day handed over nothing. At the end of every
/// export (finished, cancelled or failed) this copies that export's `recap` and
/// `routing` lines into a file in Application Support, and `DiagnosticsLog`
/// appends the file to what it shares. The most recent
/// `export.pipeline.kept_export_logs` exports are kept.
///
/// **§0.** These are the very lines `DiagnosticsLog` already shares — counts,
/// durations and fixed words, values not marked public read back redacted —
/// now also kept on this device. Nothing is sent anywhere: sharing stays the
/// person's own action, one file at a time.
enum ExportLogHistory {
    /// The line that opens each export's block — what `appending` splits on.
    static let blockMark = "=== export "

    /// Reads the export's lines off the main actor and appends them as one block.
    /// A failure is logged and dropped: bookkeeping must never fail an export.
    static func keep(since start: Date, keptExports: Int, file: URL? = defaultFile) {
        guard keptExports > 0, let file else { return }
        Task.detached(priority: .utility) {
            do {
                let lines = try readLines(since: start)
                let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let text = appending(block: block(start: start, lines: lines), to: existing, keeping: keptExports)
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try text.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                KamomeLog.storage.error("export log history: could not keep this export's lines — \(error)")
            }
        }
    }

    /// What has been kept, or nil when nothing has.
    static func read(file: URL? = defaultFile) -> String? {
        guard let file, let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// Pure, so the rolling cut is testable without a log store: `block`
    /// appended to `existing`, then only the last `keeping` blocks survive.
    static func appending(block: String, to existing: String, keeping: Int) -> String {
        let blocks = (existing + block).components(separatedBy: blockMark)
            .filter { !$0.isEmpty }
            .map { blockMark + $0 }
        return blocks.suffix(max(keeping, 0)).joined()
    }

    static func block(start: Date, lines: [DiagnosticsLog.Line]) -> String {
        DiagnosticsLog.render(header: [blockMark + DiagnosticsLog.localStamp(start)], lines: lines)
    }

    static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("export-history.txt")
    }

    private static func readLines(since start: Date) throws -> [DiagnosticsLog.Line] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(date: start),
            matching: NSPredicate(
                format: "subsystem == %@ AND (category == %@ OR category == %@)",
                KamomeLog.subsystem, "recap", "routing"
            )
        )
        return entries.compactMap { entry in
            guard let log = entry as? OSLogEntryLog, log.date >= start else { return nil }
            return DiagnosticsLog.Line(log)
        }
    }
}
