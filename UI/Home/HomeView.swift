import KamomeTrackingEngine
import SwiftUI
import UIKit

/// **Your Journeys** — the Journey Discovery home (2026-09-17).
///
/// The first screen is the journeys Kamome found in the photo library, by
/// year, each a card that already knows where it went. Nothing is created until
/// a card is opened; the manual import sheet and live recording stay reachable
/// from the toolbar menu, as the paths for a journey the library cannot see.
struct HomeView: View {
    @Environment(TrackingSession.self) private var session
    @State private var model: JourneyDiscoveryModel
    @State private var path: [String] = []
    @State private var showingImport = false
    @State private var showingRecord = false
    @State private var showingAbout = false
    @State private var showingFirstRunNotice = false
    @State private var deleting: JourneySummary?
    @Namespace private var cardNamespace
    #if DEBUG
    @State private var debugShareFile: DebugShareFile?
    #endif

    init(session: TrackingSession) {
        _model = State(initialValue: HomeView.makeModel(session: session))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle(Text("home_title"))
            .navigationDestination(for: String.self) { tripId in
                TripDetailView(tripId: tripId, session: session)
                    .modifier(ZoomFromCard(id: model.summary(forTrip: tripId)?.id ?? tripId, namespace: cardNamespace))
            }
            .refreshable { await model.refresh() }
            .fullScreenCover(isPresented: .constant(session.isRecording)) {
                RecordingView()
            }
            .sheet(isPresented: $showingImport) {
                ImportSheet(session: session) { tripId in
                    showingImport = false
                    session.refreshTrips()
                    model.loadTrips()
                    path = [tripId]
                }
            }
            .sheet(isPresented: $showingRecord) {
                StartRecordingSheet(session: session)
                    .presentationDetents([.medium])
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
            .confirmationDialog(
                "journey_delete_confirm", isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }
                ), titleVisibility: .visible
            ) {
                Button("journey_delete", role: .destructive) {
                    if let deleting { withAnimation(.snappy) { model.delete(deleting) } }
                    session.refreshTrips()
                    deleting = nil
                }
            }
            .toolbar { toolbarItems }
            #if DEBUG
            .sheet(item: $debugShareFile) { file in
                ActivityShareSheet(url: file.url)
            }
            #endif
        }
        .task { await model.refresh() }
        .onChange(of: session.trips.count) { model.loadTrips() }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo-open-trip"),
               let first = session.trips.first {
                path = [first.id]
            }
            if ProcessInfo.processInfo.arguments.contains("-demo-open-import") {
                showingImport = true
            }
            #endif
            // Told once, before this build can send a real coordinate anywhere
            // (Chiu 2026-09-04; ADR 2026-09-05 (b)). Checked against the demo
            // sheet above: two sheets raised in one pass is a race, not a stack.
            if !showingImport, FirstRunNotice.shouldPresent(matching: session.config.matching) {
                showingFirstRunNotice = true
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .undetermined where !model.hasJourneys:
            WelcomeCard(isWorking: model.isScanning) {
                Task { await model.requestAccessAndDiscover() }
            }
            .padding(.top, 8)
        case .denied where !model.hasJourneys:
            AccessDeniedCard { showingImport = true }
                .padding(.top, 8)
        default:
            journeyList
        }
    }

    private var journeyList: some View {
        LazyVStack(alignment: .leading, spacing: 28, pinnedViews: []) {
            if model.isScanning {
                ScanningRow()
                    .transition(.opacity)
            }
            if model.isLimitedAccess {
                LimitedLibraryRow { model.selectMorePhotos() }
            }
            ForEach(model.sections) { section in
                yearSection(section)
            }
            if !model.hasJourneys, !model.isScanning {
                NothingFoundCard(access: model.access) { showingImport = true }
            }
        }
        .padding(.top, 4)
        .animation(.snappy(duration: 0.45), value: model.sections)
    }

    private func yearSection(_ section: JourneyYearSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: String(section.year))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(section.journeys) { journey in
                JourneyCard(
                    journey: journey,
                    isOpening: model.openingId == journey.id,
                    namespace: cardNamespace
                ) {
                    open(journey)
                }
                .contextMenu { contextMenu(for: journey) }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for journey: JourneySummary) -> some View {
        if journey.isImported {
            Button(role: .destructive) { deleting = journey } label: {
                Label("journey_delete", systemImage: "trash")
            }
        } else {
            Button { withAnimation(.snappy) { model.hide(journey) } } label: {
                Label("journey_hide", systemImage: "eye.slash")
            }
        }
    }

    private func open(_ journey: JourneySummary) {
        Task {
            if let tripId = await model.open(journey) {
                session.refreshTrips()
                path.append(tripId)
            }
        }
    }

    // MARK: - Toolbar

    /// One trailing item, deliberately (2026-09-02: two `ToolbarItem`s at the
    /// trailing edge lost the info button on relaunch). The info button is the
    /// licence obligation's anchor (`Docs/release-readiness.md` S2) and stays a
    /// button of its own; the two ways to add a journey the library cannot see
    /// share a menu beside it.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        #if DEBUG
        ToolbarItem(placement: .topBarLeading) { debugExportMenu }
        #endif
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                Menu {
                    Button { showingImport = true } label: {
                        Label("import_from_photos", systemImage: "photo.stack")
                    }
                    Button { showingRecord = true } label: {
                        Label("live_capture_header", systemImage: "record.circle")
                    }
                } label: {
                    Label("journey_add", systemImage: "plus")
                }
                Button { showingAbout = true } label: {
                    Label("about_title", systemImage: "info.circle")
                }
            }
        }
    }

    private static func makeModel(session: TrackingSession) -> JourneyDiscoveryModel {
        #if DEBUG
        if let demo = DemoJourneyLibrary.ifRequested() {
            return JourneyDiscoveryModel(
                config: session.config, repository: session.repository,
                source: demo, photoAccess: demo, defaults: demo.defaults
            )
        }
        #endif
        return JourneyDiscoveryModel(
            config: session.config,
            repository: session.repository,
            source: PhotoLibraryImportSource(),
            photoAccess: PhotoLibraryService(config: session.config, repository: session.repository)
        )
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

/// The card grows into its screen on iOS 18; on 17 the push is the plain one.
private struct ZoomFromCard: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
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
