#if DEBUG
import Foundation
import UIKit

/// Drive-test aid for the Phase 1 device gate (Docs/device-test-P1.md):
/// appends battery and engine events to a CSV so the checklist's drain
/// number comes from data, not memory. Event-driven only — logs on trip
/// start/end, dwell transitions, and whenever iOS reports a battery-level
/// change — so there is no polling interval to tune. Debug builds only.
final class DriveTestLog {
    static let shared = DriveTestLog()

    let fileURL: URL
    private var observer: NSObjectProtocol?

    /// Local time with UTC offset (e.g. 2026-07-16T10:44:20+08:00) so the
    /// checklist reviewer can line entries up with the drive without
    /// converting from UTC.
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    private init() {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = (support ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("drive-test-log.csv")
    }

    var hasEntries: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func tripStarted(vehicle: String) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        append(event: "trip_start", detail: vehicle)
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.append(event: "battery_change")
        }
    }

    func tripEnded(discardedAsPhantom: Bool = false) {
        append(event: "trip_end", detail: discardedAsPhantom ? "phantom_discarded" : "")
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    func dwellPaused() {
        append(event: "dwell_pause")
    }

    func dwellResumed() {
        append(event: "dwell_resume")
    }

    private func append(event: String, detail: String = "") {
        let device = UIDevice.current
        let percent = device.batteryLevel < 0 ? "" : String(Int(device.batteryLevel * 100))
        let state: String
        switch device.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        let line = [
            timestampFormatter.string(from: .now),
            event, percent, state, detail
        ].joined(separator: ",") + "\n"

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            let header = "timestamp,event,battery_pct,battery_state,detail\n"
            try? ((header + line).data(using: .utf8) ?? data).write(to: fileURL)
        }
    }
}
#endif
