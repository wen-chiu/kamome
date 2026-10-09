import SwiftUI

/// **足跡 / Footprints** — Home's second segment (ADR draft
/// 2026-09-30-footprints-sits-beside-journeys). It was the Journey Discovery
/// beta, a sheet behind a toolbar button, until it left beta.
///
/// Kamome finds the journeys already sitting in the photo library and lays them
/// out as one chronology: year, then destination and date, then the route. Each
/// entry folds its photographs and details into a drawer that opens in place
/// (2026-09-23); tapping the entry opens its itinerary, which only reads.
///
/// **For reading, not making.** Import, recording, editing, deleting and
/// export all live in 旅程 / Journeys (S1 → S3). Here a found journey can be
/// hidden, and a stored one has no delete (「刪除只在旅程」).
///
/// **Built only when first shown** (§0): `HomeView` creates the model the
/// first time 足跡 is chosen, and the scan starts on this view's first
/// appearance — never at launch, which always opens on 旅程 (Chiu 2026-10-07).
struct FootprintsView: View {
    let model: JourneyDiscoveryModel
    /// Pushes a journey's itinerary on Home's stack.
    let onOpen: (JourneySummary) -> Void
    /// Shared with Home, whose stack draws the itinerary the entry grows into.
    let namespace: Namespace.ID

    /// Entries whose drawer is open. Several may be; opening one closes nothing.
    @State private var expanded: Set<String> = []
    @State private var showingHidden = false

    var body: some View {
        ScrollView {
            state
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.refresh() }
        // The first appearance scans; a return reads the trips again, since a
        // journey made here has been named and routed since (#169).
        .task {
            if model.phase == .idle {
                await model.refresh()
            } else {
                model.loadTrips()
            }
        }
    }

    // MARK: - Content

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
                        isNaming: model.awaitsName(journey),
                        isLast: isLastOverall(section: sectionIndex, entry: index),
                        namespace: namespace,
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
            if !model.hiddenJourneys.isEmpty {
                HiddenJourneysRow(journeys: model.hiddenJourneys, isExpanded: $showingHidden) { journey in
                    withAnimation(.snappy) { model.unhide(journey) }
                }
                .padding(.top, 24)
                .transition(.opacity)
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

    /// A found journey can be hidden; a stored trip has nothing here. Delete
    /// lives only in Journeys (Footprints ADR draft).
    @ViewBuilder
    private func contextMenu(for journey: JourneySummary) -> some View {
        if FootprintsMenu.canHide(journey) {
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

    /// A journey opens its itinerary. Nothing is imported until
    /// 「新增旅程」 (Footprints ADR draft: a found journey is previewed).
    private func open(_ journey: JourneySummary) {
        onOpen(journey)
    }

    static func makeModel(session: TrackingSession) -> JourneyDiscoveryModel {
        #if DEBUG
        if let demo = DemoJourneyLibrary.ifRequested() {
            return JourneyDiscoveryModel(
                config: session.config, repository: session.repository,
                source: demo, photoAccess: demo, defaults: demo.defaults,
                matchesTripsByPhotographs: false
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

/// What a Footprints entry's menu offers. Its own type so the rule is tested:
/// a stored trip in Footprints has no delete, and nothing else.
enum FootprintsMenu {
    static func canHide(_ journey: JourneySummary) -> Bool {
        !journey.isImported
    }
}

/// The entry grows into its diary on iOS 18; on 17 the push is the plain one.
struct ZoomFromEntry: ViewModifier {
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
