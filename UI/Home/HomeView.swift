import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer
import SwiftUI
import UIKit

/// S1 Home / Trip List: trip rows with a cover photograph (`HomeTripRow`), the
/// import hero button, and a quieter "Record a trip" button that asks for the
/// vehicle in its own sheet (Chiu 2026-09-23).
///
/// ⚠️ **This screen stays the home** (Chiu, 2026-09-18). Footprints sits beside
/// it as a second segment, 旅程 | 足跡 (ADR draft
/// 2026-09-30-footprints-sits-beside-journeys), on this one stack: everything
/// in 旅程 — the trip list, import, live capture, the licence anchor — works
/// exactly as it did. Footprints is built the first time it is chosen.
struct HomeView: View {
    @Environment(TrackingSession.self) private var session
    @State private var vehicle: VehicleType = .car
    @State private var path: [HomeRoute] = []
    @State private var segment = HomeSegment.atLaunch
    /// Created the first time 足跡 is chosen, never before (§0), and kept for
    /// the session so its scan and its names are not redone on every switch.
    @State private var footprints: JourneyDiscoveryModel?
    @Namespace private var entryNamespace
    @State private var showingImport = false
    @State private var showingStartRecording = false
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
            Group {
                switch segment {
                case .journeys: journeys
                case .footprints: footprintsContent
                }
            }
            .navigationTitle(Text(segment.title))
            // The segmented control already names the page; a large title
            // under it said it twice and cost the list ~80 pt (Chiu
            // 2026-10-07). The title still names the back button.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self, destination: destination)
            .fullScreenCover(isPresented: .constant(session.isRecording)) {
                RecordingView()
            }
            .sheet(isPresented: $showingImport) {
                // On success: dismiss the sheet, refresh the list so the new
                // trip appears, and push straight to S3 (Trip Detail).
                ImportSheet(session: session) { tripId in
                    showingImport = false
                    session.refreshTrips()
                    path = [.trip(tripId)]
                }
            }
            .sheet(isPresented: $showingStartRecording) {
                StartRecordingSheet(vehicle: $vehicle, access: session.locationAccess) {
                    session.requestStart(vehicle: vehicle)
                }
            }
            .onChange(of: session.isRecording) {
                // The sheet waits for the location prompt (#190) and makes way
                // for S2 only once a recording has really begun.
                if session.isRecording { showingStartRecording = false }
            }
            .toolbar { toolbarItems }
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
                path = [.trip(first.id)]
            }
            // Replay MVP §1 artifact: present the import sheet for its shot.
            if ProcessInfo.processInfo.arguments.contains("-demo-open-import") {
                showingImport = true
            }
            if ProcessInfo.processInfo.arguments.contains("-demo-discover") {
                show(.footprints)
            }
            // The record sheet's own shot (Chiu 2026-09-23 home cleanup).
            if ProcessInfo.processInfo.arguments.contains("-demo-open-record") {
                showingStartRecording = true
            }
            #endif
            // Told once, before this build can send a real coordinate anywhere
            // (Chiu 2026-09-04; ADR 2026-09-05 (b)). The demo sheets above are
            // checked because they open from this same `onAppear`, and two
            // sheets raised in one pass is a race rather than a stack. Nothing
            // is remembered on the launch that loses it, so the notice comes
            // back on the next one.
            if !showingImport, !showingStartRecording,
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
        // The segments sit at `.principal`, never beside the info button: two
        // items at `.topBarTrailing` lost it on relaunch (2026-09-02).
        ToolbarItem(placement: .principal) {
            HomeSegmentPicker(segment: segment, choose: show)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingAbout = true
            } label: {
                Label("about_title", systemImage: "info.circle")
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

    /// Creates the sample trip and opens it. Only offered while Home is empty,
    /// so there is at most one unless the person deletes it and asks again.
    private func openSample() throws {
        let tripId = try SampleTrip.create(repository: session.repository, vehicleId: LastVehicleChoice.forNewTrip())
        session.refreshTrips()
        path = [.trip(tripId)]
    }

    /// 旅程: the trips, and the two ways to add one held at the foot of the
    /// screen (Chiu 2026-10-07). They used to sit under the list behind a
    /// `Spacer`, which left a short list a thin strip above an empty middle;
    /// now the list runs the whole height and scrolls under them.
    private var journeys: some View {
        Group {
            if session.trips.isEmpty {
                ScrollView {
                    HomeEmptyState(openSample: openSample)
                }
            } else {
                tripList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                importButton
                recordButton
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            // The page's own background, faded in over the top edge, so a row
            // scrolling under the buttons goes out softly and a short list
            // shows no panel at all.
            .background {
                LinearGradient(
                    stops: [
                        .init(color: Color(.systemBackground).opacity(0), location: 0),
                        .init(color: Color(.systemBackground), location: 0.2)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var tripList: some View {
        List(session.trips) { trip in
            NavigationLink(value: HomeRoute.trip(trip.id)) {
                HomeTripRow(trip: trip, repository: session.repository)
            }
            // With no large title above it, the first row's top rule hung
            // under the toolbar on its own; rows are still divided below.
            .listRowSeparator(.hidden, edges: .top)
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

// MARK: - 足跡 / Footprints

extension HomeView {
    /// 足跡, once its model exists. It is created by `show(.footprints)`, so
    /// nothing here runs before the person chooses it.
    @ViewBuilder
    fileprivate var footprintsContent: some View {
        if let footprints {
            FootprintsView(model: footprints, onOpen: { path.append(.itinerary($0.id)) }, namespace: entryNamespace)
        }
    }

    /// Chooses a segment. 足跡 is built the first time; coming back to 旅程
    /// reads the trips again, since Footprints can make one.
    fileprivate func show(_ choice: HomeSegment) {
        if choice == .footprints, footprints == nil {
            footprints = FootprintsView.makeModel(session: session)
        }
        if choice == .journeys, segment != .journeys { session.refreshTrips() }
        segment = choice
    }

    /// Both itinerary actions end here: switch to 旅程 and show the trip in S3
    /// (「新增旅程」 / 「在旅程中打開」, Footprints ADR draft).
    fileprivate func openInJourneys(_ tripId: String) {
        show(.journeys)
        path = [.trip(tripId)]
    }

    @ViewBuilder
    fileprivate func destination(_ route: HomeRoute) -> some View {
        switch route {
        case .trip(let tripId):
            TripDetailView(tripId: tripId, session: session)
        case .itinerary(let id):
            if let footprints, let journey = footprints.journeys.first(where: { $0.id == id }) {
                JourneyItineraryView(summary: journey, model: footprints, onOpenTrip: openInJourneys)
                    .modifier(ZoomFromEntry(id: id, namespace: entryNamespace))
            }
        }
    }
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
