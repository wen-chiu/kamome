import Foundation

/// One journey as the home screen shows it — whether it is a stored trip or a
/// journey discovered in the library and not yet imported. The card draws this
/// and nothing else, so the two origins cannot look different by accident.
struct JourneySummary: Identifiable, Equatable {
    enum Provenance: Equatable {
        /// Kamome recorded the GPS.
        case recorded
        /// Reconstructed from photograph positions and times.
        case fromPhotos
    }

    /// The discovery key when there is one, else the trip id. A discovered
    /// journey keeps its id when it becomes a trip, so the card does not jump.
    let id: String
    /// nil until the journey is imported.
    let tripId: String?
    let discoveryKey: String?
    /// The destination, once resolved.
    var name: JourneyName?
    /// What the card says before the destination is known — the trip's own
    /// title, or the month for a journey not yet imported.
    let fallbackTitle: String
    let startedAt: Double
    let endedAt: Double
    let photoCount: Int
    let stopCount: Int
    let coverAssetIds: [String]
    /// Known only when the trip carries stats (recordings do; imports do not,
    /// `HANDOFF.md` finding 8). Shown when known, never invented.
    let distanceM: Double?
    /// `TransportMode` raw values the legs carry, **in trip order** — the
    /// timeline draws them between the places they join, so the order is the
    /// information.
    let legModes: [String]
    /// The named places this journey passed through, in order. Empty for a
    /// journey that has not been imported and geocoded yet.
    let milestones: [String]
    let provenance: Provenance
    let filmCount: Int
    /// Where the name is looked up. Never drawn.
    let nameLookupLat: Double?
    let nameLookupLon: Double?
    /// Under `discovery.single_place_extent_m` — named after the town, not the country.
    let isSinglePlace: Bool

    var headline: String { name?.title ?? fallbackTitle }
    var isImported: Bool { tripId != nil }
    var modes: Set<String> { Set(legModes) }

    /// Calendar days the journey covers, both ends counted, in the current zone.
    var dayCount: Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date(timeIntervalSince1970: startedAt))
        let to = calendar.startOfDay(for: Date(timeIntervalSince1970: endedAt))
        return max(1, (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1)
    }

    var year: Int {
        Calendar.current.component(.year, from: Date(timeIntervalSince1970: startedAt))
    }

    /// "3–15 Mar 2026" style range, in the user's locale.
    var dateRangeText: String {
        let start = Date(timeIntervalSince1970: startedAt)
        let end = Date(timeIntervalSince1970: endedAt)
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }
}

/// The home screen's year groups, newest first.
struct JourneyYearSection: Identifiable, Equatable {
    let year: Int
    let journeys: [JourneySummary]
    var id: Int { year }
}
