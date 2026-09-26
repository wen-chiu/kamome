import KamomeConfig
import KamomePersistence
import Observation

/// One trip's film photo plan and the person's choices over it (ADR 2026-09-24,
/// Chiu 2026-09-25).
///
/// The plan is not re-derived here: it is `RecapComposer.filmPlan`, the same
/// selection the export composes, so a number this screen draws on a photograph
/// is that photograph's place in the finished film. Shared by the Stop Editor
/// and the export sheet — the two places someone decides what a film shows.
///
/// The app chooses first; the person corrects. A stop's deck is the app's until
/// the person touches it, and from then on it is exactly what they picked.
@Observable
@MainActor
final class FilmPhotoChoices {
    private(set) var detail: TripRepository.TripDetail?
    /// Stop id → the film's deck for that stop, as asset ids in deck order.
    /// A stop absent here is not in the film.
    private(set) var decks: [String: [String]] = [:]
    /// Every stop the film could present, in trip order.
    private var eligibleStops: [StopRecord] = []

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

    /// The most photographs a stop can show, whoever chose them.
    var maxPhotos: Int { config.photoImport.deckHighlightMaxPhotos }

    /// The stops the film presents, in trip order.
    var filmStops: [StopRecord] {
        eligibleStops.filter { decks[$0.id] != nil }
    }

    /// How many photographs the film shows, across every stop it presents —
    /// the "M photos" of the line above Export (Chiu 2026-09-26).
    var filmPhotoCount: Int {
        filmStops.reduce(0) { $0 + filmDeck(for: $1.id).count }
    }

    /// The stops the film could present and does not: the app ranked them out,
    /// or the person took them out. A stop with no photographs is only listed
    /// when the person took it out — otherwise it would be noise (a fuel stop),
    /// and a stop taken out must always be reachable to put back.
    var otherStops: [StopRecord] {
        eligibleStops.filter { stop in
            decks[stop.id] == nil
                && (!usablePhotos(for: stop.id).isEmpty || stop.stopFilmChoice == .excluded)
        }
    }

    func reload() {
        detail = Stored.read("detail") { try repository.detail(tripId: tripId) }
        let plan = detail.map { RecapComposer.filmPlan(detail: $0, config: config) }
        decks = plan?.decks ?? [:]
        eligibleStops = plan?.stops ?? []
    }

    /// Every photograph at the stop, in time order — the grid shows all of them,
    /// the ones left out included, so leaving one out can be undone.
    func photos(for stopId: String) -> [PhotoRefRecord] {
        (detail?.photos ?? [])
            .filter { $0.stopId == stopId }
            .sorted { ($0.takenAt ?? 0, $0.phAssetId) < ($1.takenAt ?? 0, $1.phAssetId) }
    }

    /// The photographs the film may use at the stop — not the ones left out.
    func usablePhotos(for stopId: String) -> [PhotoRefRecord] {
        photos(for: stopId).filter { $0.isExcluded == 0 }
    }

    func isInFilm(stopId: String) -> Bool { decks[stopId] != nil }

    func filmDeck(for stopId: String) -> [String] { decks[stopId] ?? [] }

    /// The person picked this stop's photographs; the app no longer does.
    func isPicked(stopId: String) -> Bool {
        photos(for: stopId).contains { $0.filmPick != 0 }
    }

    func isTakenOut(stopId: String) -> Bool {
        eligibleStops.first { $0.id == stopId }?.stopFilmChoice == .excluded
    }

    // MARK: - Photographs

    /// What a tap on a photograph did.
    enum ToggleOutcome: Equatable {
        case changed
        /// The deck already holds `maxPhotos`; nothing changed.
        case full
        /// This is the deck's last photograph: removing it takes the stop out
        /// of the film, which the screen asks about first. Nothing changed.
        case wouldEmptyStop
    }

    /// A tap on a photograph (Chiu 2026-09-25): a numbered one leaves the deck,
    /// any other joins it. The first tap turns the app's deck into the person's
    /// — the photographs they did not touch stay where they were. Tapping a
    /// photograph at a stop that is out puts the stop in.
    func toggle(_ photo: PhotoRefRecord, stopId: String) -> ToggleOutcome {
        var deck = filmDeck(for: stopId)
        if let index = deck.firstIndex(of: photo.phAssetId) {
            guard deck.count > 1 else { return .wouldEmptyStop }
            deck.remove(at: index)
        } else {
            guard deck.count < maxPhotos else { return .full }
            deck.append(photo.phAssetId)
        }
        let byAsset = Dictionary(photos(for: stopId).map { ($0.phAssetId, $0.id) }, uniquingKeysWith: { first, _ in first })
        let photoIds = deck.compactMap { byAsset[$0] }
        Stored.write("setStopPicks") { try repository.setStopPicks(stopId: stopId, photoIds: photoIds) }
        if isTakenOut(stopId: stopId) {
            Stored.write("setStopFilmChoice") { try repository.setStopFilmChoice(stopId: stopId, choice: nil) }
        }
        changed()
        return .changed
    }

    /// Hands the stop's deck back to the app.
    func resetToAuto(stopId: String) {
        Stored.write("setStopPicks") { try repository.setStopPicks(stopId: stopId, photoIds: []) }
        changed()
    }

    /// Leaves one photograph out of every deck the app picks, or lets it back.
    func setChoice(_ choice: PhotoRefRecord.FilmChoice, photo: PhotoRefRecord) {
        Stored.write("setPhotoFilmChoice") { try repository.setPhotoFilmChoice(photoId: photo.id, choice: choice) }
        changed()
    }

    // MARK: - Stops

    /// Puts a stop in the film. The film grows; no other stop leaves.
    func putIn(stopId: String) {
        Stored.write("setStopFilmChoice") { try repository.setStopFilmChoice(stopId: stopId, choice: .included) }
        changed()
    }

    /// Takes a stop out of the film. Nothing takes its place. `clearPicks`
    /// when its last picked photograph is what took it out, so putting it back
    /// starts from the app's deck rather than from that one photograph.
    func takeOut(stopId: String, clearPicks: Bool = false) {
        if clearPicks {
            Stored.write("setStopPicks") { try repository.setStopPicks(stopId: stopId, photoIds: []) }
        }
        Stored.write("setStopFilmChoice") { try repository.setStopFilmChoice(stopId: stopId, choice: .excluded) }
        changed()
    }

    private func changed() {
        reload()
        onChange()
    }
}
