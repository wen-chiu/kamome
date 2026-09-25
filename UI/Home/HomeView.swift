import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer
import SwiftUI
import UIKit

/// S1 Home / Trip List: trip cards (title, date, distance, stops), the import
/// hero button, and a quieter "Record a trip" button that asks for the vehicle
/// in its own sheet (Chiu 2026-09-23). Cover map thumbnails remain a later polish.
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
    @State private var showingStartRecording = false
    @State private var showingDiscovery = false
    @State private var showingAbout = false
    @State private var showingFirstRunNotice = false
    /// The trip a swipe asked to delete, held until the user confirms. A full
    /// swipe used to delete outright — a recording, films and all, gone for
    /// good with no way back (arch review 2026-09-24, P0-4).
    @State private var tripPendingDeletion: TripRecord?
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
                recordButton
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
            .sheet(isPresented: $showingStartRecording) {
                StartRecordingSheet(vehicle: $vehicle) {
                    showingStartRecording = false
                    session.start(vehicle: vehicle)
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
            // The record sheet's own shot (Chiu 2026-09-23 home cleanup).
            if ProcessInfo.processInfo.arguments.contains("-demo-open-record") {
                showingStartRecording = true
            }
            #endif
            // Told once, before this build can send a real coordinate anywhere
            // (Chiu 2026-09-04; ADR 2026-09-05 (b)). Both demo sheets above are
            // checked because they open from this same `onAppear`, and two
            // sheets raised in one pass is a race rather than a stack. Nothing
            // is remembered on the launch that loses it, so the notice comes
            // back on the next one.
            if !showingImport, !showingDiscovery, !showingStartRecording,
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

    /// A recording cannot be made again; an imported trip can, from the same
    /// photos — so the two are warned differently. The imported wording is
    /// Discovery's own, the same delete seen from another screen.
    private var deletionPrompt: LocalizedStringKey {
        guard let trip = tripPendingDeletion, !trip.tripSource.isReconstructed else {
            return "journey_delete_confirm"
        }
        return "trip_delete_recorded_confirm"
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(for: trip))
                            .font(.headline)
                        HStack(spacing: 4) {
                            Text(Self.dateRangeText(startedAt: trip.startedAt, endedAt: trip.endedAt))
                            if let stats = TripStats.from(jsonString: trip.statsJson) {
                                Text(String(format: "· %.0f km · %d", stats.distanceM / 1000, stats.stopCount))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    provenanceMark(trip.tripSource)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    tripPendingDeletion = trip
                } label: {
                    Label("trip_delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
        .confirmationDialog(
            deletionPrompt, isPresented: Binding(
                get: { tripPendingDeletion != nil }, set: { if !$0 { tripPendingDeletion = nil } }
            ), titleVisibility: .visible
        ) {
            Button("trip_delete", role: .destructive) {
                if let tripPendingDeletion { session.deleteTrip(tripPendingDeletion.id) }
                tripPendingDeletion = nil
            }
        }
        .navigationDestination(for: String.self) { tripId in
            TripDetailView(tripId: tripId, session: session)
        }
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

    /// Live capture is secondary, not hidden (Chiu 2026-09-23: 「不是主力，但
    /// 想用的人要用得到」). A full-width button that names its action, with the
    /// same `location.fill` glyph a recorded trip carries in the list, so the
    /// two ways in read as a pair. It used to be a caption, a segmented vehicle
    /// picker and a bare "Start Journey" — three controls, one of which looked
    /// like it applied to import too. The vehicle is asked in the sheet.
    private var recordButton: some View {
        Button {
            showingStartRecording = true
        } label: {
            Label("record_trip", systemImage: "location.fill")
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
