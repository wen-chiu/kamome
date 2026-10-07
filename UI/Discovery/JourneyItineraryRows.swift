import KamomeExportEngine
import SwiftUI

/// **The days.** Each day is an anchor; under it, the travel that led to each
/// place and the place it reached, with the photographs taken there hanging off
/// the same rail. Read it with every photograph removed and it is still an
/// account of a journey. Moved from the beta's diary (`JourneyDiary`) when it
/// became read-only; the rows no longer open a stop editor.
struct ItineraryDays: View {
    let itinerary: JourneyItinerary

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(itinerary.days.enumerated()), id: \.element.id) { dayIndex, day in
                ItineraryDayAnchor(day: day, isFirst: dayIndex == 0)
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    if let leg = entry.leg {
                        ItineraryLegRow(leg: leg)
                    }
                    ItineraryPlaceRow(
                        place: entry.place,
                        time: itinerary.arrivalTime(of: entry.place),
                        isLast: isLastRow(dayIndex: dayIndex, entryIndex: entryIndex)
                    )
                }
            }
            if !itinerary.routePhotoAssetIds.isEmpty {
                TimelineRow(marker: .place, connectsDown: false, markerOffset: 10, bottomPadding: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("route_photos_header")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MemoryRow(
                            assetIds: Array(itinerary.routePhotoAssetIds.prefix(4)),
                            total: itinerary.routePhotoAssetIds.count, side: 62
                        )
                    }
                }
            }
        }
    }

    private func isLastRow(dayIndex: Int, entryIndex: Int) -> Bool {
        guard itinerary.routePhotoAssetIds.isEmpty else { return false }
        return dayIndex == itinerary.days.count - 1 && entryIndex == (itinerary.days.last?.entries.count ?? 0) - 1
    }
}

/// `DAY 2 ───────── Tue, 4 Aug` — the editorial rule that makes a page of
/// events read as a chronology.
private struct ItineraryDayAnchor: View {
    let day: JourneyItinerary.Day
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
private struct ItineraryPlaceRow: View {
    let place: JourneyItinerary.Place
    let time: String
    let isLast: Bool

    var body: some View {
        TimelineRow(marker: .place, connectsDown: !isLast, markerOffset: 9, bottomPadding: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let name = place.name {
                    Text(verbatim: name)
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
                if let note = place.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                if !place.photoAssetIds.isEmpty {
                    MemoryRow(
                        assetIds: Array(place.photoAssetIds.prefix(4)), total: place.photoAssetIds.count, side: 62
                    )
                    .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// **The travel between two places**: a glyph on the rail and how well its
/// line is known. No distance: kilometres are S3's. An inferred leg is an
/// honest account of a journey nobody watched, said quietly, never a warning.
private struct ItineraryLegRow: View {
    let leg: JourneyItinerary.Leg

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

    private var text: LocalizedStringKey {
        if leg.isCrossing { return "leg_crossing" }
        switch leg.provenance {
        case .recorded: return "leg_recorded"
        case .reconstructed: return "leg_matched"
        case .inferred: return "leg_inferred"
        }
    }
}
