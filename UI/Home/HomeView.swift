import KamomeTrackingEngine
import KamomeTripComposer
import SwiftUI
import UIKit

/// S1 Home / Trip List: trip cards (title, date, distance, stops), vehicle
/// selector, big Start button. Cover map thumbnails remain a later polish.
///
/// ⚠️ **This screen stays the home** (Chiu, 2026-09-18). Journey Discovery is an
/// *added* feature in beta, not a replacement: it is one toolbar button away and
/// opens as its own screen, so everything below — the trip list, import, live
/// capture, the licence anchor — keeps working exactly as it did while the new
/// UI is refined. Nothing here was restyled for it.
struct HomeView: View {
    @Environment(TrackingSession.self) private var session
    @State private var vehicle: VehicleType = .car
    @State private var path: [String] = []
    @State private var showingImport = false
    @State private var showingDiscovery = false
    @State private var showingAbout = false
    @State private var showingFirstRunNotice = false
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
                importButton
                liveCaptureSection
            }
            .padding()
            .navigationTitle(Text("home_title"))
            .fullScreenCover(isPresented: .constant(session.isRecording)) {
                RecordingView()
            }
            .sheet(isPresented: $showingImport) {
                // On success: dismiss the sheet, refresh the list so the new
                // trip appears, and push straight to S3 (Trip Detail).
                ImportSheet(session: session) { tripId in
                    showingImport = false
                    session.refreshTrips()
                    path = [tripId]
                }
            }
            .toolbar { toolbarItems }
            .sheet(isPresented: $showingDiscovery) {
                JourneyTimelineView(session: session)
            }
            .onChange(of: showingDiscovery) {
                // The beta can create a trip (opening a discovered journey
                // imports it) and can delete one, so the list behind it is
                // refreshed on the way back rather than left stale.
                if !showingDiscovery { session.refreshTrips() }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView(matching: session.config.matching)
            }
            .sheet(isPresented: $showingFirstRunNotice) {
                FirstRunNoticeView(matching: session.config.matching) {
                    FirstRunNotice.acknowledge()
                    showingFirstRunNotice = false
                }
            }
            #if DEBUG
            .sheet(item: $debugShareFile) { file in
                ActivityShareSheet(url: file.url)
            }
            #endif
        }
        .onAppear {
            #if DEBUG
            // Demo screenshot automation (Phase 2 gate): jump straight to S3.
            if ProcessInfo.processInfo.arguments.contains("-demo-open-trip"),
               let first = session.trips.first {
                path = [first.id]
            }
            // Replay MVP §1 artifact: present the import sheet for its shot.
            if ProcessInfo.processInfo.arguments.contains("-demo-open-import") {
                showingImport = true
            }
            if ProcessInfo.processInfo.arguments.contains("-demo-discover") {
                showingDiscovery = true
            }
            #endif
            // Told once, before this build can send a real coordinate anywhere
            // (Chiu 2026-09-04; ADR 2026-09-05 (b)). Both demo sheets above are
            // checked because they open from this same `onAppear`, and two
            // sheets raised in one pass is a race rather than a stack. Nothing
            // is remembered on the launch that loses it, so the notice comes
            // back on the next one.
            if !showingImport, !showingDiscovery,
               FirstRunNotice.shouldPresent(matching: session.config.matching) {
                showingFirstRunNotice = true
            }
        }
    }

    /// Home is the only screen every user reaches, so it is where the licence
    /// obligation can be relied on to be reachable (`Docs/release-readiness.md`
    /// S2). ⏳ The placement is Chiu's and is not ruled on — this is the anchor
    /// that already existed, not a chosen design.
    ///
    /// **The debug menu moves to the leading side rather than sharing this one**
    /// (2026-09-02). Two `ToolbarItem`s at `.topBarTrailing` are not two buttons:
    /// the info button rendered on a first launch and was **gone on every clean
    /// relaunch after it**, which is the worst possible failure for a licence
    /// obligation — present when you check it, absent when a user looks. The
    /// debug menu keeps its own slot instead of being deleted, because it is the
    /// post-drive data path (`Docs/device-test-P1.md`) and a verification route
    /// is not something to trade for a toolbar corner.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        #if DEBUG
        ToolbarItem(placement: .topBarLeading) { debugExportMenu }
        #endif
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 2) {
                Button {
                    showingDiscovery = true
                } label: {
                    Label("discovery_open", systemImage: "sparkles.rectangle.stack")
                }
                Button {
                    showingAbout = true
                } label: {
                    Label("about_title", systemImage: "info.circle")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("empty_state_pitch")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("empty_state_import_hint")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal)
    }

    private var tripList: some View {
        List(session.trips) { trip in
            NavigationLink(value: trip.id) {
                VStack(alignment: .leading, spacing: 4) {
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
                    // Honest provenance (§3): a trip rebuilt from photo EXIF is
                    // never presented as recorded/verified.
                    if trip.tripSource.isReconstructed {
                        provenanceBadge
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { tripId in
            TripDetailView(tripId: tripId, session: session)
        }
    }

    private var provenanceBadge: some View {
        Label("provenance_badge", systemImage: "photo.on.rectangle")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
            .foregroundStyle(.secondary)
    }

    // MP4-from-photos is the hero action (§5 S1); live capture is secondary and
    // graduates to Capture Beta (Phase 5).
    private var importButton: some View {
        Button {
            showingImport = true
        } label: {
            Label("import_from_photos", systemImage: "photo.stack")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    private var liveCaptureSection: some View {
        VStack(spacing: 8) {
            Text("live_capture_header")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            vehiclePicker
            startButton
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
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
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
