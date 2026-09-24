import Foundation
import KamomeConfig
import OSLog
import UIKit

/// **What a TestFlight device run leaves behind, handed over by the tester**
/// (ADR 2026-09-24 (d), Chiu: an "Export diagnostics" row in About).
///
/// A TestFlight build is a Release build, so `DriveTestLog` and the debug export
/// menu are compiled out, and D1–D5 (export time, memory, seconds per snapshot)
/// were readable only with the phone on a Mac in Console. This reads Kamome's
/// own unified-log lines back from this launch and writes them to a text file
/// the tester shares by hand.
///
/// **§0.** Only `subsystem:com.chiu.kamome`, and every `KamomeLog` line is
/// written to carry counts, durations and fixed strings — never a coordinate or
/// a place (the rule each call site already keeps). Values logged without
/// `privacy: .public` come back redacted. Nothing is sent anywhere: the share
/// sheet is the user's own action, one file at a time.
///
/// **Only this launch.** `OSLogStore` in an app sees its own process, so a run
/// that crashed took its lines with it — export right after the thing being
/// measured, before leaving the app.
enum DiagnosticsLog {
    struct Line: Equatable {
        let date: Date
        let category: String
        let level: String
        let message: String
    }

    /// The file to share, in tmp; nil when the log store cannot be opened.
    static func export(now: Date = .now) -> URL? {
        do {
            let text = render(header: header(now: now), lines: try readThisLaunch())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kamome-diagnostics-\(Int(now.timeIntervalSince1970)).txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            KamomeLog.storage.error("diagnostics export failed: \(error)")
            return nil
        }
    }

    /// Pure, so the format is testable without a log store.
    static func render(header: [String], lines: [Line]) -> String {
        let formatter = ISO8601DateFormatter()
        // Local time with its offset — Chiu reads these by hand against a drive.
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = lines.map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.level) \($0.message)" }
        return (header + ["", "\(lines.count) lines"] + body).joined(separator: "\n") + "\n"
    }

    private static func header(now: Date) -> [String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? "?"
        }
        return [
            "Kamome diagnostics — this launch only",
            "app \(version) (\(build)) · \(model) · iOS \(UIDevice.current.systemVersion)",
            "exported \(ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: .withInternetDateTime))"
        ]
    }

    private static func readThisLaunch() throws -> [Line] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            matching: NSPredicate(format: "subsystem == %@", KamomeLog.subsystem)
        )
        return entries.compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }
            return Line(date: log.date, category: log.category, level: level(log.level), message: log.composedMessage)
        }
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .error: return "ERROR"
        case .fault: return "FAULT"
        case .notice: return "notice"
        case .info: return "info"
        case .debug: return "debug"
        default: return "-"
        }
    }
}
