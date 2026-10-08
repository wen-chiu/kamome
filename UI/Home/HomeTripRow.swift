import KamomeImportKit
import KamomePersistence
import SwiftUI

/// **One trip on Home (旅程)** — read the way a Footprints entry reads, so the
/// two segments are one app (Chiu 2026-10-07): the flag and the serif name,
/// the same words for the same figures, the same kilometres, and provenance
/// marked by exception (ADR 2026-09-23 (e)). A cover photograph leads the row;
/// a trip with none shows a route tile instead.
///
/// Split out of `HomeView` (arch review 2026-09-26, round 2) as
/// `HomeView+TripRow`; a view of its own since its figures are read per row.
struct HomeTripRow: View {
    let trip: TripRecord
    let repository: TripRepository

    /// Read when the row appears, never for rows the list has not drawn.
    @State private var figures: HomeTripFigures?

    private let coverSide: CGFloat = 56

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At an accessibility size the cover sits above the words: beside
        // them it left the name a few letters and broke "271 公里" in two.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            cover
            VStack(alignment: .leading, spacing: 4) {
                headline
                facts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: trip) { figures = HomeTripFigures.load(trip: trip, repository: repository) }
    }

    @ViewBuilder
    private var cover: some View {
        if let assetId = figures?.coverAssetId {
            PhotoThumbnail(assetId: assetId, targetPx: Int(coverSide * 3))
                .frame(width: coverSide, height: coverSide)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: coverSide, height: coverSide)
                .overlay {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
        }
    }

    private var headline: some View {
        let parts = Self.headline(for: trip, clock: figures?.clock ?? .uniform())
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let flag = parts.flag {
                Text(verbatim: flag).font(.headline)
            }
            Text(verbatim: parts.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The dates, then the figures. On one line while it fits; at a large text
    /// size the two halves used to wrap separately and interleave
    /// ("2026 · 2 / 年10 km"), so they stack and each stays whole (#191).
    private var facts: some View {
        let dates = datesText
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            provenanceMark
            if let figures {
                let line = Self.figuresText(groundM: figures.groundM, stopCount: figures.stopCount)
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: "\(dates) · \(line)")
                    // Without the fixed height the fallback is measured one line
                    // tall and a long range is cut with an ellipsis, not wrapped.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: dates)
                        Text(verbatim: line)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(verbatim: dates)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// **By exception**, as in Footprints: nearly every trip is rebuilt from
    /// photographs, so a recording carries a location glyph and the sample its
    /// sparkle; a photo trip carries nothing. VoiceOver says all three.
    @ViewBuilder
    private var provenanceMark: some View {
        if let symbol = Self.provenanceSymbol(trip.tripSource) {
            Image(systemName: symbol)
                .font(.caption2)
        }
    }

    /// Counted in the stops' own zones once the row has read them (#171);
    /// until then, the phone's — which is the same date for nearly every trip.
    private var datesText: String {
        Self.dateRangeText(startedAt: trip.startedAt, endedAt: trip.endedAt, clock: figures?.clock ?? .uniform())
    }

    private var accessibilityText: String {
        let parts = Self.headline(for: trip, clock: figures?.clock ?? .uniform())
        var spoken = [
            parts.title,
            datesText,
            String(localized: Self.provenanceKey(trip.tripSource))
        ]
        if let figures {
            spoken.append(Self.figuresText(groundM: figures.groundM, stopCount: figures.stopCount))
        }
        return spoken.joined(separator: ", ")
    }
}

// MARK: - Text

extension HomeTripRow {
    /// The row's headline: the trip's real name when it has one (an album's,
    /// or one the user typed) with the flag of the place found for it —
    /// otherwise that place, by `TripTitle`'s rule (flag + town, region or
    /// country), falling back to the plain date range until that one-time
    /// lookup resolves, or forever if it never finds one.
    static func headline(
        for trip: TripRecord,
        cache: JourneyNameCache = JourneyNameCache(),
        homeCountryCode: String? = JourneyNameCache.deviceHomeCountryCode,
        clock: TripClock = .uniform()
    ) -> (flag: String?, title: String) {
        let flag = TripTitle.flag(for: trip, cache: cache, homeCountryCode: homeCountryCode)
        guard TripTitle.isFallback(trip) else { return (flag, trip.title) }
        if let place = TripTitle.place(for: trip, cache: cache, homeCountryCode: homeCountryCode) {
            // `place` is "🇨🇦 Whitehorse": the flag is split off to be set in
            // its own size, as Footprints sets it.
            if let flag, place.hasPrefix(flag + " ") {
                return (flag, String(place.dropFirst(flag.count + 1)))
            }
            return (nil, place)
        }
        return (nil, dateRangeText(startedAt: trip.startedAt, endedAt: trip.endedAt, clock: clock))
    }

    /// "Jun 21 – 22, 2026" — the same span format the Import sheet's own album
    /// rows already use; a single day collapses to one date. Home has no year
    /// headings, so the year stays in. The dates are the local ones where the
    /// trip began and ended (`TripClock`, #171), as on the boarding pass.
    static func dateRangeText(startedAt: Double, endedAt: Double?, clock: TripClock = .uniform()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let span = clock.localDateSpan(startedAt: startedAt, endedAt: endedAt ?? startedAt)
        let from = formatter.string(from: span.first)
        guard endedAt != nil, !Calendar.current.isDate(span.first, inSameDayAs: span.last) else { return from }
        return "\(from) – \(formatter.string(from: span.last))"
    }

    /// "271 km · 4 places" — Footprints' words for Footprints' figures: the
    /// kilometres on the ground (`LegLength.groundMeters`), only from a
    /// kilometre up, and the stops counted as places. The count carries its
    /// unit: a bare number read as a stray digit, most of all the zero of a
    /// recording with no stops (#192).
    static func figuresText(groundM: Double?, stopCount: Int) -> String {
        var parts: [String] = []
        if let groundM, groundM >= 1000 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_km"), groundM / 1000))
        }
        parts.append(String.localizedStringWithFormat(String(localized: "journey_places"), stopCount))
        return parts.joined(separator: " · ")
    }

    /// nil for a trip rebuilt from photographs: marked by exception.
    static func provenanceSymbol(_ source: TripSource) -> String? {
        if source.isSample { return "sparkles" }
        return source.isReconstructed ? nil : "location.fill"
    }

    static func provenanceKey(_ source: TripSource) -> String.LocalizationValue {
        if source.isSample { return "sample_badge" }
        return source.isReconstructed ? "provenance_badge" : "provenance_recorded"
    }
}

/// What a Home row reads from the store, once per appearance: the same facts a
/// Footprints entry is built from, so the two cannot disagree about one trip.
struct HomeTripFigures: Equatable {
    let groundM: Double?
    let stopCount: Int
    let coverAssetId: String?
    /// The stops' zones, so the row's dates are where the trip happened.
    let clock: TripClock

    static func load(trip: TripRecord, repository: TripRepository) -> HomeTripFigures? {
        guard let facts = Stored.read("journeyCardFacts", { try repository.journeyCardFacts(tripId: trip.id) })
        else { return nil }
        let cover = PhotoCoverSelector.select(
            facts.photos.map { PhotoCoverSelector.Candidate(assetId: $0.phAssetId, isHighlight: $0.isHighlight == 1) },
            count: 1
        ).first
        return HomeTripFigures(
            groundM: LegLength.groundMeters(trip: trip, repository: repository),
            stopCount: facts.stopCount,
            coverAssetId: cover,
            clock: TripClock(stops: facts.stops)
        )
    }
}
