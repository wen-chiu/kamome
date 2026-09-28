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

    /// The story's headline, by Home's rule: a real name (an album's, a
    /// Discovery card's, or one the person typed) wins; only a trip still
    /// titled with its plain start date shows the place found for it. Without
    /// this the cached place hid a rename on this screen.
    var storyTitle: String {
        guard let trip = detail?.trip else { return "" }
        guard TripTitle.isFallback(trip) else { return trip.title }
        return journeyName?.title ?? trip.title
    }
}
