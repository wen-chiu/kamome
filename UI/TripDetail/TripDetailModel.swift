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
    private let repository: TripRepository
    private let config: TrackingConfig
    private let photoService: PhotoLibraryService
    private let namer: StopNamer

    init(tripId: String, config: TrackingConfig, repository: TripRepository) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
        photoService = PhotoLibraryService(config: config, repository: repository)
        namer = StopNamer(config: config.geocode, repository: repository)
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
        reload()
        guard let detail else { return }

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
        let unnamed = detail.stops.filter(StopNamer.needsName)
        if !unnamed.isEmpty {
            // Reload as each name lands, not once on a timer: a photo-dense
            // imported trip has many stops geocoded over ~30 s (§4.2 throttle),
            // well past any single refresh.
            namer.nameUnnamedStops(unnamed) { [weak self] progress in
                self?.naming = progress
                self?.scheduleReload()
            }
        }
        // The film's HUD pill names the town (ADR 2026-09-24 (e)); stops named
        // before schema v9 are asked once, behind any naming.
        namer.fillMissingLocalities(detail.stops)
    }

    /// Resumes Vision over this trip's photographs — every trip imported
    /// before it existed, and any run the system cut short (ADR 2026-09-25 (c)).
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

    func reload() {
        detail = Stored.read("detail") { try repository.detail(tripId: tripId) }
        films = Stored.read("films") { try repository.films(tripId: tripId) } ?? []
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

    // MARK: - Days (S3 filter chips)

    /// Calendar days (`TripDay`, Chiu 2026-09-25): chip N is the trip's Nth date.
    var dayCount: Int {
        guard let detail, let endedAt = detail.trip.endedAt else { return 1 }
        return TripDay.count(startedAt: detail.trip.startedAt, endedAt: endedAt)
    }

    /// The date chip `day` (0-based) stands for.
    func date(ofDay day: Int) -> Date? {
        guard let detail else { return nil }
        return TripDay.date(ofDay: day, tripStartedAt: detail.trip.startedAt)
    }

    func selectDay(_ day: Int?) {
        selectedDay = day
    }

    func dayIndex(of timestamp: Double) -> Int {
        guard let detail else { return 0 }
        return TripDay.index(of: timestamp, tripStartedAt: detail.trip.startedAt)
    }

    var visibleStops: [StopRecord] {
        guard let detail else { return [] }
        guard let selectedDay else { return detail.stops }
        return detail.stops.filter { dayIndex(of: $0.arrivedAt) == selectedDay }
    }

    var visibleSegments: [(segment: SegmentRecord, points: [TrackpointRecord])] {
        guard let detail else { return [] }
        guard let selectedDay else { return detail.segments }
        return detail.segments.filter { dayIndex(of: $0.segment.startedAt) == selectedDay }
    }

    /// Display polyline per segment, Douglas-Peucker-thinned (§4.4).
    func displayPolyline(for points: [TrackpointRecord]) -> [Simplifier.Point] {
        Simplifier.douglasPeucker(
            points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) },
            epsilonM: config.simplify.epsilonM
        )
    }

    var stats: TripStats? {
        TripStats.from(jsonString: detail?.trip.statsJson)
    }

    // MARK: - The story (Journey Discovery detail, 2026-09-17)

    /// The name the home card resolved for this journey, if it did. Read from
    /// the same cache the card writes, so the two screens cannot disagree.
    var journeyName: JourneyName? {
        guard let detail else { return nil }
        let lats = detail.stops.map(\.lat)
        let lons = detail.stops.map(\.lon)
        var extentM = 0.0
        if let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() {
            extentM = Geo.distanceM(latA: minLat, lonA: minLon, latB: maxLat, lonB: maxLon)
        }
        return JourneyNameCache().name(
            for: detail.trip.discoveryKey ?? detail.trip.id,
            homeCountryCode: JourneyNameCache.deviceHomeCountryCode,
            isSinglePlace: extentM < config.discovery.singlePlaceExtentM
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
                date: TripDay.date(ofDay: day, tripStartedAt: detail.trip.startedAt),
                entries: grouped[day] ?? []
            )
        }
    }

    /// Every segment that starts in `[from, to]`, folded into one connector.
    private func storyLeg(between from: Double, and to: Double, id: String) -> StoryLeg? {
        guard let detail else { return nil }
        let inside = detail.segments.filter { $0.segment.startedAt >= from - 1 && $0.segment.startedAt <= to + 1 }
        guard !inside.isEmpty else { return nil }
        var modes: [TransportMode] = []
        var distance = 0.0
        var provenance = RouteProvenance.recorded
        var crossing = false
        for item in inside {
            let mode = TransportMode(rawValue: item.segment.mode) ?? .unknown
            if modes.last != mode { modes.append(mode) }
            distance += Self.length(of: item)
            let claim = RecapComposer.provenance(for: item.segment)
            if claim == .inferred || (claim == .reconstructed && provenance == .recorded) { provenance = claim }
            crossing = crossing || RecapComposer.isCrossing(item.segment)
        }
        return StoryLeg(id: "leg-\(id)", modes: modes, provenance: provenance, distanceM: distance, isCrossing: crossing)
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
        photoService.isLimitedAccess
    }

    /// True for photo-reconstructed trips — drives the S3 provenance note (§3).
    var isReconstructed: Bool {
        detail?.trip.tripSource.isReconstructed ?? false
    }

    /// Opens the system picker so a limited selection can grow, then
    /// re-matches: photos added there should land on this trip immediately.
    func manageLimitedPhotoSelection() {
        photoService.presentLimitedLibraryPicker { [weak self] in
            self?.rematchPhotos()
        }
    }

    private func rematchPhotos() {
        guard let detail, let endedAt = detail.trip.endedAt else { return }
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
