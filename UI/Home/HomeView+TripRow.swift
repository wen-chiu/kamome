import KamomePersistence
import SwiftUI

/// How one trip reads on Home: its headline, its dates, its place and its
/// provenance glyph. Split out of `HomeView` (arch review 2026-09-26, round 2)
/// when `UI/` came under SwiftLint: the struct body was 285 lines against 250.
/// Moved as written; only `private` is gone, which a separate file needs.
extension HomeView {
    /// The card's headline: the trip's real name when it has one (an album's,
    /// or one the user typed) — otherwise the place `TripJourneyNaming` found
    /// for it (flag + country), falling back to the plain date range until
    /// that one-time lookup resolves, or forever if it never finds one.
    func headline(for trip: TripRecord) -> String {
        guard hasFallbackTitle(trip) else { return trip.title }
        return placeText(for: trip) ?? Self.dateRangeText(startedAt: trip.startedAt, endedAt: trip.endedAt)
    }

    /// A trip whose stored title is still the plain fallback date — nobody
    /// named it (no album title, no Discovery card, never renamed). The only
    /// case this screen may show something else instead; a real name is never
    /// replaced.
    func hasFallbackTitle(_ trip: TripRecord) -> Bool {
        trip.title == Self.fallbackTitle(for: trip.startedAt)
    }

    static func fallbackTitle(for startedAt: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: startedAt))
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

    /// Reads the place `TripJourneyNaming` cached at trip creation — the same
    /// cache Journey Discovery writes, so a trip that came from the beta
    /// already has an entry and costs no new lookup here. First stop's
    /// country only (§0 scope, see `TripJourneyNaming`); nil until the
    /// one-time lookup resolves, or if it never finds one.
    func placeText(for trip: TripRecord) -> String? {
        guard let place = JourneyNameCache().place(for: trip.discoveryKey ?? trip.id),
              let country = place.country
        else { return nil }
        let flag = JourneyNaming.flag(countryCode: place.countryCode)
        return [flag, country].compactMap { $0 }.joined(separator: " ")
    }

    /// A single small glyph, not a text pill — the distinction (reconstructed
    /// from photos vs. a recorded track) matters for honesty (§3), not enough
    /// to earn a label competing with the title on every row. VoiceOver still
    /// gets the full word via the accessibility label.
    func provenanceMark(_ source: TripSource) -> some View {
        let symbol = source.isReconstructed ? "photo.on.rectangle" : "location.fill"
        let key: LocalizedStringKey = source.isReconstructed ? "provenance_badge" : "provenance_recorded"
        return Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(key))
    }
}
