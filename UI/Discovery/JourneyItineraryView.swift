import SwiftUI

/// **A journey's itinerary — the Footprints diary** (ADR draft
/// 2026-09-30-footprints-sits-beside-journeys). When you went where: the
/// masthead, then each day, its places with their times, and the photographs
/// taken there.
///
/// **Read-only.** It has no map, no kilometres, no stop editing, no ride, no
/// films and no film button: all of those live in S3, and the same flow in two
/// places is the drift ADR 2026-09-18 (b) warned about. Its one action is
/// 「新增旅程」 on a found journey, 「在旅程中打開」 on a stored one; both end
/// in S3.
///
/// **A found journey is previewed, not stored.** Nothing is written and
/// nothing is routed until 「新增旅程」. Its places are named while this
/// screen is open (`PreviewStopNamer`), and leaving it cancels the rest.
struct JourneyItineraryView: View {
    let summary: JourneySummary
    let model: JourneyDiscoveryModel
    /// The trip to show in S3, after either action.
    let onOpenTrip: (String) -> Void

    @State private var itinerary: JourneyItinerary?
    /// The places whose name is still coming. Any other unnamed place says
    /// so, as S3 does, rather than "identifying" with nothing asking (#264).
    @State private var naming: Set<String> = []

    var body: some View {
        ScrollView {
            if let itinerary {
                VStack(alignment: .leading, spacing: 22) {
                    ItineraryMasthead(summary: summary, itinerary: itinerary)
                    ItineraryDays(itinerary: itinerary, naming: naming)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .onAppear(perform: load)
        .onDisappear { model.previewNamer.cancel() }
        // A stored trip's stops may be named by S3's run while this is open.
        .onChange(of: summary.tripId.flatMap { StopNamingCoordinator.shared.progress[$0] }) { reload() }
        .alert(
            Text("journey_open_failed"),
            isPresented: Binding(
                get: { model.openFailure != nil }, set: { if !$0 { model.acknowledgeOpenFailure() } }
            ),
            presenting: model.openFailure
        ) { _ in
        } message: { failure in
            // A tap that produced no trip used to produce nothing at all: the
            // spinner stopped and the screen stayed as it was (#166).
            switch failure {
            case .notATrip: Text("journey_open_failed_not_a_trip")
            case .saveFailed: Text("import_error_save")
            }
        }
    }

    private func load() {
        guard let itinerary = reload(), !itinerary.isStored else { return }
        model.previewNamer.name(itinerary.places) { reload() }
        // The places just queued are now drawn as naming.
        reload()
    }

    @discardableResult
    private func reload() -> JourneyItinerary? {
        let fresh = model.itinerary(for: summary)
        itinerary = fresh
        let unnamed = fresh?.places.filter { $0.name == nil } ?? []
        if let tripId = fresh?.tripId {
            naming = Set(unnamed.map(\.id).filter { StopNamingCoordinator.shared.isNaming(tripId, anyOf: [$0]) })
        } else {
            naming = Set(unnamed.filter(model.previewNamer.isNaming).map(\.id))
        }
        return fresh
    }

    // MARK: - The one action

    private var isCreating: Bool { model.openingId == summary.id }

    private var actionBar: some View {
        Button(action: act) {
            HStack(spacing: 8) {
                if isCreating { ProgressView().tint(.white) }
                Text(summary.isImported ? "footprints_open_in_journeys" : "footprints_create_journey")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isCreating || itinerary == nil)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func act() {
        if let tripId = summary.tripId {
            onOpenTrip(tripId)
            return
        }
        Task {
            // A refused import says why, in the alert above (#166).
            if let tripId = await model.open(summary) { onOpenTrip(tripId) }
        }
    }
}

/// **The masthead — words, not a photograph**: when, where, how long, and how
/// the journey is known. A found journey says it is not in Journeys yet.
private struct ItineraryMasthead: View {
    let summary: JourneySummary
    let itinerary: JourneyItinerary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dates)
                .font(.caption.weight(.semibold))
                .modifier(SmallCaps(tracking: 0.8))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let flag = summary.name?.flag {
                    Text(flag).font(.title)
                }
                Text(verbatim: summary.headline)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(figures)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(
                    summary.provenance == .fromPhotos ? "story_provenance_photos" : "story_provenance_recorded",
                    systemImage: summary.provenance == .fromPhotos ? "photo.on.rectangle" : "location"
                )
                if !itinerary.isStored {
                    Label("footprints_unsaved", systemImage: "circle.dashed")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The list's form with its year (#267): `.long` printed 「2026/8/3至2026/8/5」 in zh-TW.
    private var dates: String {
        JourneyDateText.rangeWithYear(from: itinerary.startedAt, to: itinerary.endedAt)
    }

    /// Photographs, places, days. No kilometres: those are S3's.
    private var figures: String {
        [
            String.localizedStringWithFormat(String(localized: "journey_photos"), itinerary.photoCount),
            String.localizedStringWithFormat(String(localized: "journey_places"), itinerary.places.count),
            String.localizedStringWithFormat(String(localized: "journey_days"), itinerary.dayCount)
        ].joined(separator: " · ")
    }
}
