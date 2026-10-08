import KamomeImportKit
import KamomePersistence
import SwiftUI

/// Picks the trips to merge with this one (ADR 2026-09-24 (b)). Reached from Trip
/// Detail's overflow menu, so Home is not restyled.
///
/// A trip whose time overlaps this one is listed but cannot be picked, so the
/// user can see why it is missing from the result. Overlaps *between* the
/// picked trips are caught by `TripMerger` and reported.
struct TripMergeSheet: View {
    let tripId: String
    let session: TrackingSession
    /// The id of the trip that survives, which may not be this one.
    let onMerged: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var merging = false
    @State private var failure: LocalizedStringKey?
    /// Each candidate's stop zones, read once, so its dates and hours are the
    /// ones where it happened (#171).
    @State private var clocks: [String: TripClock] = [:]

    private var current: TripRecord? { session.trips.first { $0.id == tripId } }

    private var candidates: [TripRecord] {
        session.trips
            .filter { $0.id != tripId && $0.endedAt != nil && !$0.tripSource.isSample }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if candidates.isEmpty {
                        Text("trip_merge_empty").foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { trip in
                        row(trip)
                    }
                } footer: {
                    Text("trip_merge_explainer")
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("trip_merge_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("import_close") { dismiss() }
                        .disabled(merging)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if merging {
                        ProgressView()
                    } else {
                        Button("trip_merge_confirm") { merge() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(merging)
            .task {
                for trip in candidates where clocks[trip.id] == nil {
                    let stops = Stored.read("stops") { try session.repository.stops(tripId: trip.id) } ?? []
                    clocks[trip.id] = TripClock(stops: stops)
                }
            }
        }
    }

    private func row(_ trip: TripRecord) -> some View {
        let blocked = overlapsCurrent(trip)
        return Button {
            if selected.contains(trip.id) {
                selected.remove(trip.id)
            } else {
                selected.insert(trip.id)
            }
        } label: {
            HStack {
                Image(systemName: selected.contains(trip.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(blocked ? Color.secondary : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: TripTitle.film(trip))
                    Group {
                        if blocked {
                            Text("trip_merge_overlap")
                        } else {
                            Text(verbatim: Self.dateRange(trip, clock: clocks[trip.id] ?? .uniform()))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: trip.tripSource.isReconstructed ? "photo.on.rectangle" : "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(blocked || merging)
    }

    private func overlapsCurrent(_ trip: TripRecord) -> Bool {
        guard let current, let currentEnd = current.endedAt, let tripEnd = trip.endedAt else { return false }
        return trip.startedAt < currentEnd && current.startedAt < tripEnd
    }

    private func merge() {
        let ids = [tripId] + selected.sorted()
        if let busy = RecapExportCoordinator.shared.running?.tripId, ids.contains(busy) {
            failure = "trip_merge_busy"
            return
        }
        merging = true
        failure = nil
        Task { @MainActor in
            do {
                let keptId = try await TripMerger.merge(
                    tripIds: ids,
                    repository: session.repository,
                    config: session.config,
                    photoService: PhotoLibraryService(config: session.config, repository: session.repository)
                )
                session.refreshTrips()
                merging = false
                dismiss()
                onMerged(keptId)
            } catch TripMerger.Refusal.overlapping {
                merging = false
                failure = "trip_merge_failed_overlap"
            } catch {
                merging = false
                failure = "trip_merge_failed"
            }
        }
    }

    /// Date and hour at each end, on the clock where that end happened
    /// (`TripClock`, #171): the hours are what tell two trips on one day apart.
    /// One zone at both ends reads as one interval; two print each end whole.
    static func dateRange(_ trip: TripRecord, clock: TripClock) -> String {
        let start = Date(timeIntervalSince1970: trip.startedAt)
        let endedAt = trip.endedAt ?? trip.startedAt
        let end = Date(timeIntervalSince1970: endedAt)
        let startZone = clock.zone(at: trip.startedAt)
        let endZone = clock.zone(at: endedAt)
        guard startZone == endZone else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.timeZone = startZone
            let from = formatter.string(from: start)
            formatter.timeZone = endZone
            return "\(from) – \(formatter.string(from: end))"
        }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = startZone
        return formatter.string(from: start, to: end)
    }
}
