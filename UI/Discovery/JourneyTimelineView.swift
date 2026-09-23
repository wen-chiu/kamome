import SwiftUI

/// **Your Journeys** — the Journey Discovery beta (Chiu, 2026-09-18).
///
/// Kamome finds the journeys already sitting in the photo library and lays them
/// out as one chronology: year, then destination and date, then the route. Each
/// entry folds its photographs and details into a drawer that opens in place
/// (2026-09-23); tapping the entry opens its diary, whose single action is
/// *Make this a Film*.
///
/// ⚠️ **It does not replace the home screen.** S1 is still the app's home and
/// still owns import and live capture; this is a separate screen reached from
/// its toolbar, so the shipping path keeps working untouched while this UI is
/// refined. That separation is Chiu's instruction, not a staging accident —
/// when the beta is judged good enough, promoting it is a decision, not a
/// leftover step.
///
/// Because the two paths stay separate, this screen deliberately carries **no**
/// import or recording entry: a journey the library cannot see is added the way
/// it always was, on the home screen behind this one.
struct JourneyTimelineView: View {
    let session: TrackingSession

    @State private var model: JourneyDiscoveryModel
    @State private var path: [String] = []
    @State private var deleting: JourneySummary?
    /// Entries whose drawer is open. Several may be; opening one closes nothing.
    @State private var expanded: Set<String> = []
    @Namespace private var entryNamespace
    @Environment(\.dismiss) private var dismiss

    init(session: TrackingSession) {
        self.session = session
        _model = State(initialValue: JourneyTimelineView.makeModel(session: session))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationTitle(Text("discovery_title"))
            .navigationDestination(for: String.self) { tripId in
                JourneyDiaryView(tripId: tripId, session: session)
                    .modifier(ZoomFromEntry(
                        id: model.summary(forTrip: tripId)?.id ?? tripId, namespace: entryNamespace
                    ))
            }
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("about_close") { dismiss() }
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
        }
        // The app follows the device's appearance (ADR 2026-09-18 (d)), so
        // this sheet inherits light or dark from the system. The light style
        // is approved (addendum to (d)).
        .task { await model.refresh() }
    }

    /// Says what this is, under the title it qualifies. A beta that does not
    /// admit to being one is just an inconsistency.
    private var betaMark: some View {
        Text("discovery_beta")
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            betaMark
                .padding(.bottom, 14)
            state
        }
    }

    @ViewBuilder
    private var state: some View {
        switch model.access {
        case .undetermined where !model.hasJourneys:
            WelcomeCard(isWorking: model.isScanning) {
                Task { await model.requestAccessAndDiscover() }
            }
            .padding(.top, 8)
        case .denied where !model.hasJourneys:
            AccessDeniedCard()
                .padding(.top, 8)
        default:
            journeyList
        }
    }

    /// **One continuous chronology**, not a list of cards. The rail runs from
    /// the first year heading to the last journey, and every entry hangs off
    /// it — which is what makes the screen read as a life of travel rather
    /// than a folder of albums.
    private var journeyList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if model.isScanning {
                ScanningRow()
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
            if model.isLimitedAccess {
                LimitedLibraryRow { model.selectMorePhotos() }
                    .padding(.bottom, 20)
            }
            let visits = model.visits
            let gaps = model.homeGaps
            ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                yearHeading(section.year, isFirst: sectionIndex == 0)
                ForEach(Array(section.journeys.enumerated()), id: \.element.id) { index, journey in
                    JourneyEntry(
                        journey: journey,
                        visit: visits[journey.id],
                        isExpanded: expanded.contains(journey.id),
                        isOpening: model.openingId == journey.id,
                        isLast: isLastOverall(section: sectionIndex, entry: index),
                        namespace: entryNamespace,
                        onToggle: { toggle(journey) },
                        action: { open(journey) }
                    )
                    .contextMenu { contextMenu(for: journey) }
                    .transition(.opacity)
                    if let days = gaps[journey.id] {
                        HomeGapRow(days: days)
                            .transition(.opacity)
                    }
                }
            }
            if !model.hasJourneys, !model.isScanning {
                NothingFoundCard(access: model.access)
            }
        }
        .padding(.top, 4)
        .animation(.snappy(duration: 0.45), value: model.sections)
    }

    /// The year, in the same editorial serif the destinations use, sitting on
    /// the rail rather than beside it.
    private func yearHeading(_ year: Int, isFirst: Bool) -> some View {
        TimelineRow(
            marker: .none, connectsUp: !isFirst, markerOffset: 16, bottomPadding: 14
        ) {
            Text(verbatim: String(year))
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func isLastOverall(section: Int, entry: Int) -> Bool {
        section == model.sections.count - 1 && entry == (model.sections.last?.journeys.count ?? 0) - 1
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

    private func toggle(_ journey: JourneySummary) {
        withAnimation(.snappy(duration: 0.3)) {
            if expanded.remove(journey.id) == nil { expanded.insert(journey.id) }
        }
    }

    private func open(_ journey: JourneySummary) {
        Task {
            if let tripId = await model.open(journey) {
                // The trip the beta just created is a real trip, so the home
                // screen behind this sheet has to know about it.
                session.refreshTrips()
                path.append(tripId)
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
}

/// The entry grows into its diary on iOS 18; on 17 the push is the plain one.
private struct ZoomFromEntry: ViewModifier {
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
