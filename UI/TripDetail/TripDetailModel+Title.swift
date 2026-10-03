import Foundation

/// The trip's own name: renaming it (S3 edit menu, Chiu 2026-09-27) and the
/// headline the story screen shows. Its own file because the model's body is
/// held to 250 lines under SwiftLint.
extension TripDetailModel {
    /// Renames the trip. Surrounding spaces go; an empty name changes nothing,
    /// so the film never opens on a blank title card.
    func renameTrip(to name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != detail?.trip.title else { return }
        Stored.write("setTripTitle") { try repository.setTripTitle(tripId: tripId, title: title) }
        reload()
    }

    /// What the rename field opens with: the trip's own name, or nothing for a
    /// trip nobody named (#177). It used to open on the stored start date,
    /// which no screen shows, and typing added to it.
    var renameDraft: String {
        guard let trip = detail?.trip, !TripTitle.isFallback(trip) else { return "" }
        return trip.title
    }

    /// The empty rename field's placeholder: what this screen calls the trip.
    var renamePrompt: String? {
        guard let trip = detail?.trip, TripTitle.isFallback(trip) else { return nil }
        return storyTitle
    }

    /// The trip's name on this screen and in the diary, by `TripTitle`'s rule: a
    /// real name (an album's, or one the person typed) wins; a trip nobody
    /// named shows the place found for it. Without this the cached place hid a
    /// rename on this screen.
    var storyTitle: String {
        guard let trip = detail?.trip else { return "" }
        guard TripTitle.isFallback(trip) else { return trip.title }
        return journeyName?.title ?? TripTitle.fallback(for: trip.startedAt)
    }

    /// The navigation bar's title: `storyTitle` with its flag, as Home's row and
    /// the film's title card say it. The stored title of an unnamed trip is its
    /// start date, which the day chips already carry.
    var screenTitle: String {
        guard let trip = detail?.trip else { return "" }
        return TripTitle.film(trip)
    }

    /// Records whether the trip stayed in one place, every time it is read.
    /// A merge or a deleted stop changes the answer, both happen on this
    /// screen, and Home's row and the film read it from the cache
    /// (`TripTitle.place`).
    func rememberExtent(under singlePlaceExtentM: Double) {
        guard let detail else { return }
        JourneyNameCache().setSinglePlace(
            TripTitle.isSinglePlace(detail.stops, under: singlePlaceExtentM),
            for: TripTitle.placeKey(for: detail.trip)
        )
    }
}
