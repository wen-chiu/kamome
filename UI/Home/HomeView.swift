import KamomeTrackingEngine
import KamomeTripComposer
import SwiftUI
import UIKit

/// S1 Home / Trip List: trip cards (title, date, distance, stops), vehicle
/// selector, big Start button. Cover map thumbnails remain a later polish.
struct HomeView: View {
    @Environment(TrackingSession.self) private var session
    @State private var vehicle: VehicleType = .car
    @State private var path: [String] = []
    #if DEBUG
    @State private var debugShareFile: DebugShareFile?
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                if session.trips.isEmpty {
                    emptyState
                } else {
                    tripList
                }
                Spacer()
                vehiclePicker
                startButton
            }
            .padding()
            .navigationTitle(Text("home_title"))
            .fullScreenCover(isPresented: .constant(session.isRecording)) {
                RecordingView()
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { debugExportMenu }
            }
            .sheet(item: $debugShareFile) { file in
                ActivityShareSheet(url: file.url)
            }
            #endif
        }
        .preferredColorScheme(.dark) // dark-mode-first: maps look better (§5)
        .onAppear {
            #if DEBUG
            // Demo screenshot automation (Phase 2 gate): jump straight to S3.
            if ProcessInfo.processInfo.arguments.contains("-demo-open-trip"),
               let first = session.trips.first {
                path = [first.id]
            }
            #endif
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bird")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("empty_state_pitch")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var tripList: some View {
        List(session.trips) { trip in
            NavigationLink(value: trip.id) {
                VStack(alignment: .leading) {
                    Text(trip.title)
                        .font(.headline)
                    HStack {
                        Text(Date(timeIntervalSince1970: trip.startedAt), style: .date)
                        if let stats = TripStats.from(jsonString: trip.statsJson) {
                            Text(String(format: "· %.0f km · %d", stats.distanceM / 1000, stats.stopCount))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { tripId in
            TripDetailView(tripId: tripId, session: session)
        }
    }

    private var vehiclePicker: some View {
        Picker("vehicle_label", selection: $vehicle) {
            Text("vehicle_car").tag(VehicleType.car)
            Text("vehicle_scooter").tag(VehicleType.scooter)
            Text("vehicle_bicycle").tag(VehicleType.bicycle)
        }
        .pickerStyle(.segmented)
    }

    private var startButton: some View {
        Button {
            session.start(vehicle: vehicle)
        } label: {
            Text("start_journey")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    #if DEBUG
    // Post-drive verification aids (Docs/device-test-P1.md): pull the raw
    // data off the phone without a tethered debugger. Debug builds only,
    // strings deliberately unlocalized.
    private var debugExportMenu: some View {
        Menu {
            Button {
                debugShareFile = Self.exportDatabase(session: session)
            } label: {
                Label { Text(verbatim: "Export database") } icon: { Image(systemName: "cylinder.split.1x2") }
            }
            Button {
                debugShareFile = Self.exportLatestTripGPX(session: session)
            } label: {
                Label { Text(verbatim: "Export latest trip as GPX") } icon: { Image(systemName: "map") }
            }
            .disabled(session.trips.isEmpty)
            Button {
                debugShareFile = DebugShareFile(url: DriveTestLog.shared.fileURL)
            } label: {
                Label { Text(verbatim: "Export drive-test log") } icon: { Image(systemName: "battery.75percent") }
            }
            .disabled(!DriveTestLog.shared.hasEntries)
        } label: {
            Image(systemName: "wrench.and.screwdriver")
        }
    }

    private static func exportDatabase(session: TrackingSession) -> DebugShareFile? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-\(Self.timestamp()).sqlite")
        do {
            try session.repository.snapshotDatabase(to: url.path)
            return DebugShareFile(url: url)
        } catch {
            return nil
        }
    }

    private static func exportLatestTripGPX(session: TrackingSession) -> DebugShareFile? {
        guard let trip = session.trips.first,
              let detail = try? session.repository.detail(tripId: trip.id) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-trip-\(Self.timestamp()).gpx")
        do {
            try GPXExporter.gpx(for: detail).write(to: url, atomically: true, encoding: .utf8)
            return DebugShareFile(url: url)
        } catch {
            return nil
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
    #endif
}

#if DEBUG
private struct DebugShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
