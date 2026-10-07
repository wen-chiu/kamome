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

    var body: some View {
        ScrollView {
            if let itinerary {
                VStack(alignment: .leading, spacing: 22) {
                    ItineraryMasthead(summary: summary, itinerary: itinerary)
                    ItineraryDays(itinerary: itinerary)
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
        itinerary = model.itinerary(for: summary)
        guard let itinerary, !itinerary.isStored else { return }
        model.previewNamer.name(itinerary.places) {
            self.itinerary = model.itinerary(for: summary)
        }
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

    private var dates: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(
            from: Date(timeIntervalSince1970: itinerary.startedAt), to: Date(timeIntervalSince1970: itinerary.endedAt)
        )
    }

    /// Photographs, places, days. No kilometres: those are S3's.
    private var figures: String {
        [
            String.localizedStringWithFormat(String(localized: "journey_photos"), itinerary.photoCount),
            String.localizedStringWithFormat(String(localized: "journey_stops"), itinerary.places.count),
            String.localizedStringWithFormat(String(localized: "journey_days"), itinerary.dayCount)
        ].joined(separator: " · ")
    }
}
