import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import Observation

/// Backs S3/S4: loads one trip, then lazily composes it — photo matching on
/// first open, reverse-geocoded names for unnamed stops.
@Observable
final class TripDetailModel {
    private(set) var detail: TripRepository.TripDetail?
    private(set) var selectedDay: Int?
    /// Films stored for this trip, newest first.
    private(set) var films: [FilmRecord] = []

    let tripId: String
    /// Not `private`: the rename in `TripDetailModel+Title.swift` writes through it.
    let repository: TripRepository
    private let config: TrackingConfig
    private let photoService: PhotoLibraryService

    init(tripId: String, config: TrackingConfig, repository: TripRepository) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
        photoService = PhotoLibraryService(config: config, repository: repository)
    }

    /// Which subject this trip's film draws. NULL in the database means the trip
    /// predates the choice, and reads as the catalogue default.
    var vehicleId: String { detail?.trip.vehicleId ?? VehicleCatalog.defaultSubjectId }

    /// What the picker offers: every selectable subject, plus this trip's own
    /// even when it is not selectable — a picker must always be able to show
    /// what is currently set, including a subject the app chose itself.
    var pickableSubjects: [VehicleSubject] {
        let selectable = VehicleCatalog.selectableSubjects
        guard !selectable.contains(where: { $0.id == vehicleId }),
              let current = VehicleCatalog.subject(id: vehicleId)
        else { return selectable }
        return [current] + selectable
    }

    /// Writes the choice to the trip and remembers it for the next one. A column
    /// write, so changing subject never costs a re-import.
    func chooseVehicle(_ vehicleId: String) {
        Stored.write("setTripVehicle") { try repository.setTripVehicle(tripId: tripId, vehicleId: vehicleId) }
        LastVehicleChoice.remember(vehicleId)
        reload()
    }

    func load() {
        // Through `reload()` so the **films** are read too. `load()` used to read
        // only the trip, which was invisible while the sheet was the only route
        // to a film: dismissing it called `reload()` and the section appeared.
        // Once an export can finish with this screen not even in the hierarchy
        // (ADR 2026-09-10), first appearance is the *only* read there is, and a
        // stored film sat on disk with nothing listing it.
        Task { @MainActor in
            await refresh()
            continueLoad()
        }
    }

    /// What `load()` does once the trip is in hand.
    @MainActor
    private func continueLoad() {
        guard let detail else { return }

        // The sample's drawings are its photographs: never matched against the
        // person's library, never analysed (ADR 2026-09-28-sample-trip).
        guard !isSample else { return }
        if detail.photos.isEmpty, let endedAt = detail.trip.endedAt {
            photoService.matchPhotos(
                tripId: tripId,
                startedAt: detail.trip.startedAt,
                endedAt: endedAt,
                stops: detail.stops
            ) { [weak self] matched in
                guard let self, matched > 0 else { return }
                reload()
                startPhotoAnalysis()
            }
        }
        startPhotoAnalysis()
        // Reload as each name lands, not once on a timer: a photo-dense
        // imported trip has many stops geocoded over ~30 s (§4.2 throttle),
        // well past any single refresh. The run belongs to the coordinator, so
        // it carries on when this screen goes and is joined when it comes back
        // (#159); towns are filled behind the names (ADR 2026-09-24 (e)), and
        // each one that lands is heard here too: the zone that comes with it is
        // what the day chips and the stops' hours are read in (ADR 2026-10-01).
        StopNamingCoordinator.shared.start(
            tripId: tripId, stops: detail.stops, first: filmStopIds, repository: repository,
            config: config.geocode, for: self
        ) { [weak self] progress in
            self?.naming = progress
            self?.scheduleReload()
        }
    }

    /// Resumes Vision over this trip's photographs — every trip imported
    /// before it existed, and any run the system cut short (ADR 2026-09-25 (d)).
    private func startPhotoAnalysis() {
        let (tripId, repository, config) = (tripId, repository, config.photoAnalysis)
        Task { @MainActor in
            PhotoAnalysisCoordinator.shared.start(tripId: tripId, repository: repository, config: config)
        }
    }

    /// How far stop naming has got, for the S3 banner and the export gate.
    private(set) var naming = StopNamer.Progress()

    /// **True while stops are still being identified.** Exporting now would bake
    /// "Unnamed stop" into the film for every stop the geocoder has not reached
    /// yet — naming is throttled at `geocode.min_interval_s`, so an 18-stop trip
    /// needs ~36 s. `RecapModel` re-reads the DB at export time, so waiting is all
    /// that is required; the UI simply has to stop offering the button first
    /// (Chiu 2026-08-04).
    var isNamingStops: Bool { naming.total > 0 && !naming.isFinished }

    /// The stops a film of this trip can open with, at either length: the
    /// export's own plan (`RecapComposer.filmPlan`), read with the trip.
    private(set) var filmStopIds: Set<String> = []

    /// **True while a stop the film shows is still being identified** (Chiu
    /// 2026-10-01, #160). The film button waits on this, not on the whole trip:
    /// a 45-stop trip shows about 21, and the rest are named behind them. The
    /// banner keeps counting every stop (`isNamingStops`).
    @MainActor var isNamingFilmStops: Bool {
        isNamingStops && StopNamingCoordinator.shared.isNaming(tripId, anyOf: filmStopIds)
    }

    /// Re-reads the trip and its films, off the main thread: `detail` carries
    /// every trackpoint, and a two-week recording made the sync read a hitch
    /// (#128). Fire-and-forget for the views; `refresh()` is the awaitable form.
    func reload() {
        Task { @MainActor in await refresh() }
    }

    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false

    /// Reads run one at a time, so an older read can never land over a newer
    /// one (a rename, a vehicle choice). A request that arrives mid-read is
    /// coalesced into one more read that starts after it, and every caller
    /// returns once that read has landed — never with stale rows.
    @MainActor
    func refresh() async {
        if let running = refreshTask {
            refreshAgain = true
            await running.value
            return
        }
        let (repository, tripId, epsilonM, config) = (repository, tripId, config.simplify.epsilonM, config)
        let task = Task { @MainActor in
            repeat {
                refreshAgain = false
                let read = await Task.detached(priority: .userInitiated) {
                    let detail = Stored.read("detail") { try repository.detail(tripId: tripId) }
                    return (detail,
                            Stored.read("films") { try repository.films(tripId: tripId) } ?? [],
                            Self.thinned(detail?.segments ?? [], epsilonM: epsilonM),
                            detail.map { Self.filmStopIds($0, config: config) } ?? [])
                }.value
                // One assignment, so the map never draws lines from another read.
                (detail, films, displayPolylines, filmStopIds) = read
                rememberExtent(under: config.discovery.singlePlaceExtentM)
            } while refreshAgain
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    /// Every stop either film length presents. Both, because the length is
    /// chosen on the export sheet, after the button this gates.
    nonisolated static func filmStopIds(_ detail: TripRepository.TripDetail, config: TrackingConfig) -> Set<String> {
        FilmLength.allCases.reduce(into: Set<String>()) { ids, length in
            ids.formUnion(RecapComposer.filmPlan(detail: detail, config: config, length: length).decks.keys)
        }
    }

    /// Deletes a single film record and its file on disk.
    func deleteFilm(_ film: FilmRecord) {
        // The file goes only once its row has: a row pointing at a deleted file
        // is a film the list shows and cannot play (same rule as `RecapModel`).
        if Stored.write("deleteFilm", { try repository.deleteFilm(filmId: film.id) }) {
            FilmStore.deleteFile(relativePath: film.relativePath)
        }
        reload()
    }

    /// Coalesces bursts of naming callbacks into at most one reload per runloop
    /// tick (nearby stops can resolve from the geocode cache synchronously).
    private var reloadScheduled = false
    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloadScheduled = false
            self.reload()
        }
    }

    func selectDay(_ day: Int?) {
        selectedDay = day
    }

    /// Each segment's display polyline, Douglas-Peucker-thinned (§4.4), keyed
    /// by segment id. Thinned in `refresh()` off the main thread, beside the read
    /// it comes from: the map bodies used to thin every segment on every render
    /// (#139).
    private(set) var displayPolylines: [String: [Simplifier.Point]] = [:]

    var stats: TripStats? {
        TripStats.from(jsonString: detail?.trip.statsJson)
    }

    // MARK: - The story (Journey Discovery detail, 2026-09-17)

    /// The name the home card resolved for this journey, if it did. Read from
    /// the same cache the card writes, so the two screens cannot disagree.
    var journeyName: JourneyName? {
        guard let detail else { return nil }
        return JourneyNameCache().name(
            for: TripTitle.placeKey(for: detail.trip),
            homeCountryCode: JourneyNameCache.deviceHomeCountryCode,
            isSinglePlace: TripTitle.isSinglePlace(detail.stops, under: config.discovery.singlePlaceExtentM)
        )
    }

    /// One stretch of travel between two stops, as the story tells it: how, how
    /// far, and how honestly the line is known. Aggregated from every segment
    /// that starts inside the gap, so a recording with many mode changes reads
    /// as one connector rather than a list.
    struct StoryLeg: Equatable, Identifiable {
        let id: String
        let modes: [TransportMode]
        /// The weakest claim any of the segments makes: inferred beats
        /// reconstructed beats recorded, because a line is only as honest as its
        /// least-known stretch.
        let provenance: RouteProvenance
        let distanceM: Double
        let isCrossing: Bool
    }

    /// The stops of one calendar day of the trip, with the connector that
    /// leads *into* each stop (nil for the first stop of the journey).
    struct StoryDay: Equatable, Identifiable {
        let index: Int
        let date: Date
        let entries: [(leg: StoryLeg?, stop: StopRecord)]
        var id: Int { index }

        static func == (lhs: StoryDay, rhs: StoryDay) -> Bool {
            lhs.index == rhs.index && lhs.entries.map(\.stop) == rhs.entries.map(\.stop)
                && lhs.entries.map(\.leg) == rhs.entries.map(\.leg)
        }
    }

    /// **The distance the diary itself adds up.** An imported trip carries no
    /// `TripStats` (`HANDOFF.md` finding 8), so this is the only total that can
    /// be told truthfully about one — and it is the sum of the very numbers the
    /// connectors below print, so a reader can check it by hand.
    var totalDistanceM: Double {
        storyDays.flatMap(\.entries).compactMap { $0.leg?.distanceM }.reduce(0, +)
    }

    var storyDays: [StoryDay] {
        guard let detail else { return [] }
        let stops = detail.stops
        var entries: [(leg: StoryLeg?, stop: StopRecord)] = []
        for (index, stop) in stops.enumerated() {
            let from = index == 0 ? detail.trip.startedAt : (stops[index - 1].departedAt ?? stops[index - 1].arrivedAt)
            let leg = index == 0 ? nil : storyLeg(between: from, and: stop.arrivedAt, id: stop.id)
            entries.append((leg, stop))
        }
        let grouped = Dictionary(grouping: entries) { dayIndex(of: $0.stop.arrivedAt) }
        return grouped.keys.sorted().map { day in
            StoryDay(
                index: day,
                date: clock.date(ofDay: day, tripStartedAt: detail.trip.startedAt),
                entries: grouped[day] ?? []
            )
        }
    }

    /// Every segment that starts in `[from, to]`, folded into one connector.
    private func storyLeg(between from: Double, and to: Double, id: String) -> StoryLeg? {
        guard let detail else { return nil }
        let inside = detail.segments.filter { $0.segment.startedAt >= from - 1 && $0.segment.startedAt <= to + 1 }
        // The one folding rule the Footprints itinerary uses too, so the two
        // screens cannot call the same leg differently.
        let pieces = inside.map { item in
            StoryLegFolding.Piece(
                startedAt: item.segment.startedAt,
                mode: TransportMode(rawValue: item.segment.mode) ?? .unknown,
                provenance: RecapComposer.provenance(for: item.segment),
                isCrossing: RecapComposer.isCrossing(item.segment)
            )
        }
        guard let folded = StoryLegFolding.fold(pieces, from: from, to: to) else { return nil }
        let distance = inside.reduce(0.0) { $0 + Self.length(of: $1) }
        return StoryLeg(
            id: "leg-\(id)", modes: folded.modes, provenance: folded.provenance,
            distanceM: distance, isCrossing: folded.isCrossing
        )
    }

    /// Along the road when one was matched, else along the raw points
    /// (`LegLength`, shared with the Discovery timeline).
    private static func length(of item: (segment: SegmentRecord, points: [TrackpointRecord])) -> Double {
        LegLength.meters(segment: item.segment, points: item.points)
    }

    func photos(for stopId: String) -> [PhotoRefRecord] {
        detail?.photos.filter { $0.stopId == stopId } ?? []
    }

    /// §4.3 route-attached photos (stop_id NULL — taken mid-drive, away from
    /// any stop): they get their own timeline strip instead of a stop's. With a
    /// day chip selected, only that day's (Chiu 2026-09-25); a photograph with
    /// no capture time belongs to no day and shows under "All" alone.
    var routePhotos: [PhotoRefRecord] {
        guard let detail else { return [] }
        let unattached = detail.photos.filter { $0.stopId == nil }
        guard let selectedDay else { return unattached }
        return unattached.filter { photo in
            photo.takenAt.map { dayIndex(of: $0) == selectedDay } ?? false
        }
    }

    var photoAccessIsLimited: Bool {
        !isSample && photoService.isLimitedAccess
    }

    /// Opens the system picker so a limited selection can grow, then
    /// re-matches: photos added there should land on this trip immediately.
    func manageLimitedPhotoSelection() {
        photoService.presentLimitedLibraryPicker { [weak self] in
            self?.rematchPhotos()
        }
    }

    private func rematchPhotos() {
        guard let detail, !isSample, let endedAt = detail.trip.endedAt else { return }
        photoService.matchPhotos(
            tripId: tripId,
            startedAt: detail.trip.startedAt,
            endedAt: endedAt,
            stops: detail.stops
        ) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: - S4 editing

    func rename(stopId: String, to name: String) {
        Stored.write("setStopName") { try repository.setStopName(stopId: stopId, name: name) }
        reload()
    }

    func setNote(stopId: String, note: String) {
        Stored.write("setStopNote") { try repository.setStopNote(stopId: stopId, note: note.isEmpty ? nil : note) }
        reload()
    }

    func deleteStop(stopId: String) {
        Stored.write("deleteStop") { try repository.deleteStop(stopId: stopId) }
        reload()
    }

    func mergeWithPrevious(stopId: String) {
        guard let detail,
              let index = detail.stops.firstIndex(where: { $0.id == stopId }),
              index > 0 else { return }
        Stored.write("mergeStops") { try repository.mergeStops(keptId: detail.stops[index - 1].id, absorbedId: stopId) }
        reload()
    }

    /// The film's photo plan for the Stop Editor's picker. A change there
    /// re-reads this trip so the timeline's stars follow.
    @MainActor
    func filmPhotoChoices() -> FilmPhotoChoices {
        FilmPhotoChoices(tripId: tripId, config: config, repository: repository) { [weak self] in
            self?.reload()
        }
    }
}
