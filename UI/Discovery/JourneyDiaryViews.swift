import KamomeExportEngine
import KamomePersistence
import KamomeTrackingEngine
import SwiftUI

/// **The masthead — words, not a photograph.**
///
/// This screen opened on a full-bleed photo cover until 2026-09-18. That made
/// the journey look like an album: the first thing the eye met was an image,
/// and the dates and the place were captions on it. A journal opens with its
/// dateline, so this does: where, when, how long, and how the route is known.
/// The photographs are further down, inside the days they belong to.
struct JourneyMasthead: View {
    let model: TripDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let trip = model.detail?.trip {
                Text(Self.dates(trip))
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let flag = model.journeyName?.flag {
                    Text(flag).font(.title)
                }
                Text(model.journeyName?.title ?? model.detail?.trip.title ?? "")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(
                model.isReconstructed ? "story_provenance_photos" : "story_provenance_recorded",
                systemImage: model.isReconstructed ? "photo.on.rectangle" : "location"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
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

/// The journey's figures as one tracked line. Deliberately **not** a row of
/// large numbers: that reads as a dashboard, and this is a dateline.
///
/// Distance appears when it can be told truthfully — from the trip's own stats
/// when it has them, else summed from the legs the diary below prints, which is
/// the same number the reader can add up by hand.
struct JourneyFigures: View {
    let model: TripDetailModel

    var body: some View {
        Text(line)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityLabel(line)
    }

    private var line: String {
        var parts = [
            String.localizedStringWithFormat(
                String(localized: "journey_photos"), model.detail?.photos.count ?? 0
            ),
            String.localizedStringWithFormat(
                String(localized: "journey_stops"), model.detail?.stops.count ?? 0
            ),
            String.localizedStringWithFormat(String(localized: "journey_days"), model.dayCount)
        ]
        let distance = model.stats?.distanceM ?? model.totalDistanceM
        if distance >= 1000 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_km"), distance / 1000))
        }
        return parts.joined(separator: " · ")
    }
}

/// **The diary.** Days are the anchors; under each, the travel that led there
/// and the place it arrived at, with the photographs taken there hanging off
/// the same rail. Read it with every photograph removed and it is still an
/// account of a journey — that is the property this layout exists to hold.
struct JourneyDiary: View {
    let model: TripDetailModel
    let onEdit: (StopRecord) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.storyDays.enumerated()), id: \.element.id) { dayIndex, day in
                DayAnchor(day: day, isFirst: dayIndex == 0)
                ForEach(Array(day.entries.enumerated()), id: \.element.stop.id) { entryIndex, entry in
                    if let leg = entry.leg {
                        LegRow(leg: leg)
                    }
                    StopRow(
                        stop: entry.stop,
                        photos: model.photos(for: entry.stop.id),
                        model: model,
                        isLast: isLastRow(dayIndex: dayIndex, entryIndex: entryIndex),
                        onEdit: onEdit
                    )
                }
            }
            if !model.routePhotos.isEmpty {
                TimelineRow(marker: .place, connectsDown: false, markerOffset: 10, bottomPadding: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("route_photos_header")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MemoryRow(
                            assetIds: model.routePhotos.prefix(4).map(\.phAssetId),
                            total: model.routePhotos.count, side: 62
                        )
                    }
                }
            }
        }
    }

    private func isLastRow(dayIndex: Int, entryIndex: Int) -> Bool {
        guard model.routePhotos.isEmpty else { return false }
        let days = model.storyDays
        return dayIndex == days.count - 1 && entryIndex == (days.last?.entries.count ?? 0) - 1
    }
}

/// `DAY 2 ───────── Tuesday, 4 Aug` — the editorial rule that makes a page of
/// events read as a chronology.
private struct DayAnchor: View {
    let day: TripDetailModel.StoryDay
    let isFirst: Bool

    var body: some View {
        TimelineRow(marker: .none, connectsUp: !isFirst, markerOffset: 14, bottomPadding: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(String.localizedStringWithFormat(String(localized: "day_chip"), day.index + 1))
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                Text(day.date, format: .dateTime.weekday(.abbreviated).day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A place, and what time the journey reached it.
private struct StopRow: View {
    let stop: StopRecord
    let photos: [PhotoRefRecord]
    let model: TripDetailModel
    let isLast: Bool
    let onEdit: (StopRecord) -> Void

    var body: some View {
        Button { onEdit(stop) } label: {
            TimelineRow(marker: .place, connectsDown: !isLast, markerOffset: 9, bottomPadding: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(Date(timeIntervalSince1970: stop.arrivedAt), style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let name = stop.name {
                        Text(name)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("story_identifying").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let note = stop.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    if !photos.isEmpty {
                        MemoryRow(
                            assetIds: photos.prefix(4).map(\.phAssetId), total: photos.count, side: 62
                        )
                        .padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(EntryPress())
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

/// **A journey event in its own right**: the travel between two places, on the
/// rail, saying how far it went and how well the line is known. Uncertainty is
/// a quiet clause here, never a warning — an inferred leg is an honest account
/// of a journey nobody watched, not a fault.
private struct LegRow: View {
    let leg: TripDetailModel.StoryLeg

    var body: some View {
        TimelineRow(marker: .transport(symbol), markerOffset: 11, bottomPadding: 22) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        leg.isCrossing ? TransportGlyph.crossing : TransportGlyph.symbol(for: leg.modes.first ?? .unknown)
    }

    private var text: String {
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
