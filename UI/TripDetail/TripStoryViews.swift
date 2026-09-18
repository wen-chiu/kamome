import KamomePersistence
import KamomeTrackingEngine
import SwiftUI

/// The hero: the journey's photographs, its name, its dates, and one line of
/// provenance — never "verified" (§3).
struct TripHero: View {
    let model: TripDetailModel
    let coverCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                JourneyCover(assetIds: model.coverAssetIds(count: coverCount))
                    .aspectRatio(stacked ? 16 / 10 : 4 / 5, contentMode: .fit)
                if !stacked {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    words.foregroundStyle(.white).padding(20)
                }
            }
            if stacked { words.padding(20) }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let flag = model.journeyName?.flag { Text(flag).font(.title) }
                Text(model.journeyName?.title ?? model.detail?.trip.title ?? "")
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
            }
            if let trip = model.detail?.trip {
                Text(Self.dates(trip)).font(.subheadline).opacity(0.85)
            }
            Label(model.isReconstructed ? "story_provenance_photos" : "story_provenance_recorded",
                  systemImage: model.isReconstructed ? "photo.on.rectangle" : "location")
                .font(.caption)
                .opacity(0.8)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private static func dates(_ trip: TripRecord) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let start = Date(timeIntervalSince1970: trip.startedAt)
        let end = Date(timeIntervalSince1970: trip.endedAt ?? trip.startedAt)
        return formatter.string(from: start, to: end)
    }
}

/// Four figures, at a glance. Distance only when the trip carries stats;
/// an imported trip does not, and the figure is left out rather than invented.
struct TripGlance: View {
    let model: TripDetailModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            figure("\(model.detail?.photos.count ?? 0)", "glance_photos")
            figure("\(model.detail?.stops.count ?? 0)", "stat_stops")
            figure("\(model.dayCount)", "glance_days")
            if let stats = model.stats, stats.distanceM >= 1000 {
                figure(String(format: "%.0f", stats.distanceM / 1000), "recap_figure_label_km")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The story itself: day by day, stop by stop, with the travel between.
struct TripStoryTimeline: View {
    let model: TripDetailModel
    let onEdit: (StopRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(model.storyDays) { day in
                dayHeader(day)
                ForEach(day.entries, id: \.stop.id) { entry in
                    if let leg = entry.leg { LegConnector(leg: leg) }
                    StopRow(stop: entry.stop, photos: model.photos(for: entry.stop.id), model: model, onEdit: onEdit)
                }
            }
            if !model.routePhotos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("route_photos_header").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    PhotoStrip(photos: model.routePhotos, maxThumbnails: 4, side: 72)
                }
            }
        }
    }

    private func dayHeader(_ day: TripDetailModel.StoryDay) -> some View {
        HStack(spacing: 8) {
            Text(String.localizedStringWithFormat(String(localized: "day_chip"), day.index + 1))
                .font(.subheadline.weight(.semibold))
            Text(day.date, format: .dateTime.weekday(.wide).day().month())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One stop: when, where, its photographs. Tapping edits; swiping merges or
/// deletes, as before.
private struct StopRow: View {
    let stop: StopRecord
    let photos: [PhotoRefRecord]
    let model: TripDetailModel
    let onEdit: (StopRecord) -> Void

    var body: some View {
        Button { onEdit(stop) } label: {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date(timeIntervalSince1970: stop.arrivedAt), style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let name = stop.name {
                        Text(name).font(.title3.weight(.semibold))
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("story_identifying").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let note = stop.note, !note.isEmpty {
                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !photos.isEmpty {
                        PhotoStrip(photos: photos, maxThumbnails: 4, side: 72)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { model.deleteStop(stopId: stop.id) } label: {
                Label("delete_stop", systemImage: "trash")
            }
            if model.visibleStops.first?.id != stop.id {
                Button { model.mergeWithPrevious(stopId: stop.id) } label: {
                    Label("merge_with_previous", systemImage: "arrow.triangle.merge")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The travel into a stop: how, how far, and how well the line is known.
/// Uncertainty is a quiet word in the caption, not a warning.
private struct LegConnector: View {
    let leg: TripDetailModel.StoryLeg

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle()
                .fill(Color.accentColor.opacity(leg.provenance == .inferred ? 0.35 : 0.7))
                .frame(width: 2, height: 28)
                .padding(.horizontal, 4)
            HStack(spacing: 6) {
                ForEach(Array(leg.modes.enumerated()), id: \.offset) { _, mode in
                    Image(systemName: Self.symbol(mode))
                }
                Text(Self.text(leg))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func symbol(_ mode: TransportMode) -> String {
        switch mode {
        case .drive: return "car.fill"
        case .scooter: return "scooter"
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .transit: return "tram.fill"
        case .unknown: return "arrow.right"
        }
    }

    private static func text(_ leg: TripDetailModel.StoryLeg) -> String {
        var parts: [String] = []
        if leg.distanceM >= 1000 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_km"), leg.distanceM / 1000))
        } else if leg.distanceM > 0 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_m"), leg.distanceM))
        }
        if leg.isCrossing {
            parts.append(String(localized: "leg_crossing"))
        } else {
            switch leg.provenance {
            case .recorded: parts.append(String(localized: "leg_recorded"))
            case .reconstructed: parts.append(String(localized: "leg_matched"))
            case .inferred: parts.append(String(localized: "leg_inferred"))
            }
        }
        return parts.joined(separator: " · ")
    }
}
