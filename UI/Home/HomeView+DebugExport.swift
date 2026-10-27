#if DEBUG
import SwiftUI
import UIKit

// Post-drive data off the phone (`Docs/device-test-P1.md`), for `HomeView`'s
// debug menu. Out of `HomeView.swift` for SwiftLint's file length (#290 took it
// past 400 lines); debug builds only, strings deliberately unlocalized.
extension HomeView {
    static func exportDatabase(session: TrackingSession) -> DebugShareFile? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-\(Self.timestamp()).sqlite")
        do {
            try session.repository.snapshotDatabase(to: url.path)
            return DebugShareFile(url: url)
        } catch {
            return nil
        }
    }

    static func exportLatestTripGPX(session: TrackingSession) -> DebugShareFile? {
        guard let trip = session.trips.first,
              let detail = Stored.read("detail", { try session.repository.detail(tripId: trip.id) }) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-trip-\(Self.timestamp()).gpx")
        do {
            try GPXExporter.gpx(for: detail).write(to: url, atomically: true, encoding: .utf8)
            return DebugShareFile(url: url)
        } catch {
            return nil
        }
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

struct DebugShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
