import KamomeConfig
import KamomePersistence
import Observation

/// One trip's film photo plan and the person's choices over it (ADR 2026-09-24).
///
/// The plan is not re-derived here: it is `RecapComposer.filmDecks`, the same
/// selection the export composes, so a number this screen draws on a photograph
/// is that photograph's place in the finished film. Shared by the Stop Editor
/// and the export sheet — the two places someone decides what a film shows.
@Observable
@MainActor
final class FilmPhotoChoices {
    private(set) var detail: TripRepository.TripDetail?
    /// Stop id → the film's deck for that stop, as asset ids in deck order.
    /// A stop absent here is not in the film.
    private(set) var decks: [String: [String]] = [:]

    let tripId: String
    private let repository: TripRepository
    private let config: TrackingConfig
    /// Called after every change, so a screen holding its own copy of the trip
    /// (Trip Detail's stars) can re-read it.
    private let onChange: () -> Void

    init(tripId: String, config: TrackingConfig, repository: TripRepository, onChange: @escaping () -> Void = {}) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
        self.onChange = onChange
        reload()
    }

    /// The most photographs a stop's stars can make it show.
    var highlightMaxPhotos: Int { config.photoImport.deckHighlightMaxPhotos }

    /// The stops the film presents with photographs to choose from, in trip
    /// order. A stop with none is a pin in the film and has nothing to pick.
    var filmStops: [StopRecord] {
        detail?.stops.filter { decks[$0.id] != nil && !photos(for: $0.id).isEmpty } ?? []
    }

    func reload() {
        detail = try? repository.detail(tripId: tripId)
        decks = detail.map { RecapComposer.filmDecks(detail: $0, config: config) } ?? [:]
    }

    /// Every photograph at the stop, in time order — the grid shows all of them,
    /// the ones left out included, so leaving one out can be undone.
    func photos(for stopId: String) -> [PhotoRefRecord] {
        (detail?.photos ?? [])
            .filter { $0.stopId == stopId }
            .sorted { ($0.takenAt ?? 0, $0.phAssetId) < ($1.takenAt ?? 0, $1.phAssetId) }
    }

    func isInFilm(stopId: String) -> Bool { decks[stopId] != nil }

    func filmDeck(for stopId: String) -> [String] { decks[stopId] ?? [] }

    func setChoice(_ choice: PhotoRefRecord.FilmChoice, photo: PhotoRefRecord) {
        try? repository.setPhotoFilmChoice(photoId: photo.id, choice: choice)
        reload()
        onChange()
    }
}
