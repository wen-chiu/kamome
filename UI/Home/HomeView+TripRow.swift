import KamomePersistence
import KamomeTripComposer
import SwiftUI

/// How one trip reads on Home: its headline, its dates, its place and its
/// provenance glyph. Split out of `HomeView` (arch review 2026-09-26, round 2)
/// when `UI/` came under SwiftLint: the struct body was 285 lines against 250.
/// Moved as written; only `private` is gone, which a separate file needs.
extension HomeView {
    /// The card's headline: the trip's real name when it has one (an album's,
    /// or one the user typed) — otherwise the place found for it, by
    /// `TripTitle`'s rule (flag + town, region or country), falling back to the
    /// plain date range until that one-time lookup resolves, or forever if it
    /// never finds one.
    func headline(for trip: TripRecord) -> String {
        guard hasFallbackTitle(trip) else { return trip.title }
        return placeText(for: trip) ?? Self.dateRangeText(startedAt: trip.startedAt, endedAt: trip.endedAt)
    }

    /// A trip whose stored title is still the plain fallback date (`TripTitle`).
    /// The only case this screen may show something else instead; a real name
    /// is never replaced.
    func hasFallbackTitle(_ trip: TripRecord) -> Bool {
        TripTitle.isFallback(trip)
    }

    /// "Jun 21 – 22, 2026" — the same span format the Import sheet's own album
    /// rows already use; a single day collapses to one date.
    static func dateRangeText(startedAt: Double, endedAt: Double?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = Date(timeIntervalSince1970: startedAt)
        let from = formatter.string(from: start)
        guard let endedAt else { return from }
        let end = Date(timeIntervalSince1970: endedAt)
        guard !Calendar.current.isDate(start, inSameDayAs: end) else { return from }
        return "\(from) – \(formatter.string(from: end))"
    }

    /// "2 km · 3 stops". The count carries its unit: a bare number read as a
    /// stray digit, most of all the zero of a recording with no stops (#192).
    static func statsText(_ stats: TripStats) -> String {
        let stops = String.localizedStringWithFormat(String(localized: "recap_film_stop_count"), stats.stopCount)
        return String(format: "%.0f km · ", stats.distanceM / 1000) + stops
    }

    /// The row's second line: the dates, then distance and stops. On one line
    /// while it fits; at a large text size the two halves used to wrap
    /// separately and interleave ("2026 · 2 / 年10 km"), so they stack and each
    /// stays whole (#191).
    @ViewBuilder
    func tripFacts(_ trip: TripRecord) -> some View {
        let dates = Self.dateRangeText(startedAt: trip.startedAt, endedAt: trip.endedAt)
        if let stats = TripStats.from(jsonString: trip.statsJson) {
            let figures = Self.statsText(stats)
            ViewThatFits(in: .horizontal) {
                Text(verbatim: "\(dates) · \(figures)")
                // Without the fixed height the fallback is measured one line
                // tall and a long range is cut with an ellipsis, not wrapped.
                VStack(alignment: .leading, spacing: 2) {
                    Text(dates)
                    Text(figures)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(dates)
        }
    }

    /// The place found for the trip (`TripTitle.place`), nil until it resolves.
    func placeText(for trip: TripRecord) -> String? {
        TripTitle.place(for: trip)
    }

    /// A single small glyph, not a text pill — the distinction (reconstructed
    /// from photos vs. a recorded track) matters for honesty (§3), not enough
    /// to earn a label competing with the title on every row. VoiceOver still
    /// gets the full word via the accessibility label.
    func provenanceMark(_ source: TripSource) -> some View {
        let symbol = source.isSample ? "sparkles" : source.isReconstructed ? "photo.on.rectangle" : "location.fill"
        let key: LocalizedStringKey = source.isSample
            ? "sample_badge" : source.isReconstructed ? "provenance_badge" : "provenance_recorded"
        return Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(key))
    }
}
