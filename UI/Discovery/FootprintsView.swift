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

    /// A `List`, not a `ScrollView`, so a found journey can be hidden with a
    /// swipe as well as from its menu (Chiu 2026-10-10, #267). Every row is
    /// drawn edge to edge with no separator, inset or minimum height, so the
    /// rail runs through the rows unbroken as it did in the stack.
    var body: some View {
        List {
            state
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.bottom, 40, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .animation(.snappy(duration: 0.45), value: model.sections)
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
            .modifier(FootprintsListRow())
        case .denied where !model.hasJourneys:
            AccessDeniedCard()
                .padding(.top, 8)
                .modifier(FootprintsListRow())
        default:
            journeyList
        }
    }

    /// **One continuous chronology**, not a list of cards. The rail runs from
    /// the first year heading to the last journey, and every entry hangs off
    /// it — which is what makes the screen read as a life of travel rather
    /// than a folder of albums.
    @ViewBuilder
    private var journeyList: some View {
        Group {
            if model.isScanning {
                ScanningRow()
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
            if model.isLimitedAccess {
                LimitedLibraryRow { model.selectMorePhotos() }
                    .padding(.bottom, 20)
            }
        }
        .padding(.top, 4)
        .modifier(FootprintsListRow())
        // One list row per element — a year, an entry, a home gap — so each
        // entry is its own row and carries its own swipe.
        let visits = model.visits
        ForEach(rows) { row in
            switch row {
            case let .year(year, isFirst):
                yearHeading(year, isFirst: isFirst)
            case let .entry(journey, isLast):
                JourneyEntry(
                    journey: journey,
                    visit: visits[journey.id],
                    isExpanded: expanded.contains(journey.id),
                    isOpening: model.openingId == journey.id,
                    isNaming: model.awaitsName(journey),
                    isLast: isLast,
                    namespace: namespace,
                    onToggle: { toggle(journey) },
                    action: { open(journey) }
                )
                .contextMenu { contextMenu(for: journey) }
                .swipeActions(edge: .trailing) { hideAction(for: journey) }
                .transition(.opacity)
                .modifier(FootprintsListRow())
            case let .gap(_, days):
                HomeGapRow(days: days)
                    .transition(.opacity)
                    .modifier(FootprintsListRow())
            }
        }
        if !model.hasJourneys, !model.isScanning {
            NothingFoundCard(access: model.access)
                .modifier(FootprintsListRow())
        }
        if !model.hiddenJourneys.isEmpty {
            HiddenJourneysRow(journeys: model.hiddenJourneys, isExpanded: $showingHidden) { journey in
                withAnimation(.snappy) { model.unhide(journey) }
            }
            .padding(.top, 24)
            .transition(.opacity)
            .modifier(FootprintsListRow())
        }
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
        .modifier(FootprintsListRow())
    }

    /// The chronology as rows, top to bottom: each year, its journeys, and
    /// the time at home under each journey that has one.
    private enum Row: Identifiable {
        case year(Int, isFirst: Bool)
        case entry(JourneySummary, isLast: Bool)
        case gap(journeyId: String, days: Int)

        var id: String {
            switch self {
            case let .year(year, _): "year-\(year)"
            case let .entry(journey, _): journey.id
            case let .gap(journeyId, _): "gap-\(journeyId)"
            }
        }
    }

    private var rows: [Row] {
        let sections = model.sections
        let gaps = model.homeGaps
        let lastId = sections.last?.journeys.last?.id
        var rows: [Row] = []
        for (index, section) in sections.enumerated() {
            rows.append(.year(section.year, isFirst: index == 0))
            for journey in section.journeys {
                rows.append(.entry(journey, isLast: journey.id == lastId))
                if let days = gaps[journey.id] { rows.append(.gap(journeyId: journey.id, days: days)) }
            }
        }
        return rows
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

    /// The same rule as the menu: a found journey can be hidden, a stored
    /// trip offers nothing here. Not destructive — the hidden row at the foot
    /// of the list shows it again (#167) — so it is grey, not red.
    @ViewBuilder
    private func hideAction(for journey: JourneySummary) -> some View {
        if FootprintsMenu.canHide(journey) {
            Button { withAnimation(.snappy) { model.hide(journey) } } label: {
                Label("journey_hide", systemImage: "eye.slash")
            }
            .tint(.gray)
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

/// A Footprints row in a `List` that draws like the stack it replaced: page
/// margins only, no separator, no row background.
///
/// **No `.buttonStyle` here.** Set on a row, `.borderless` turned that row's
/// swipe actions off (VERIFIED 2026-10-10: four lists side by side on the
/// simulator, only the borderless one would not swipe). A default-style button
/// that must answer only its own tap sets the style itself.
private struct FootprintsListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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
