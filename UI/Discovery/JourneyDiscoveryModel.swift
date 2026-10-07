import Foundation
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer
import Observation

/// Backs the Journey Discovery home (2026-09-17): the photo library →
/// `JourneyDetector` → journey cards, with stored trips shown beside them.
///
/// **Nothing is written until the user opens a journey.** A scan is in memory;
/// `open` is what turns a discovered journey into an `imported_photos` trip
/// through the unchanged `ImportService`, and what starts routing — the same
/// user-initiated moment the import sheet always was. The one automatic side
/// effect is naming: one coarse reverse-geocode per journey (`PlaceGeocoding`),
/// throttled at `geocode.min_interval_s`, cached on device by journey.
@MainActor
@Observable
final class JourneyDiscoveryModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case ready
    }

    private(set) var access: PhotoReadAccess = .undetermined
    private(set) var phase: Phase = .idle
    /// Every journey, newest first: stored trips and discovered ones together.
    private(set) var journeys: [JourneySummary] = []
    /// Found journeys the person hid, newest first, for the row at the foot of
    /// the list that shows them again (Chiu 2026-10-03, #167). Never named:
    /// a hidden journey costs no lookup.
    private(set) var hiddenJourneys: [JourneySummary] = []
    /// Set while a discovered journey is being imported on the way to its screen.
    private(set) var openingId: String?
    /// Why the last `open` produced no trip, until the screen has said so (#166).
    private(set) var openFailure: OpenFailure?

    enum OpenFailure: Equatable {
        /// The import refused the photographs as not a trip.
        case notATrip
        /// The photographs were fine; storing the trip failed.
        case saveFailed
    }

    let config: TrackingConfig
    let repository: TripRepository
    private let provider: ImportPhotoProviding
    private let photoAccess: PhotoAccessProviding
    private let geocoder: PlaceGeocoding
    /// For a journey that has just become a trip (`nameNow`): the same lookup
    /// as a card's, asked at the priority of a new trip's flag (#159).
    private let tripGeocoder: PlaceGeocoding
    let nameCache: JourneyNameCache
    /// A found journey's places, named while its preview is open (Data 3).
    let previewNamer: PreviewStopNamer
    private let dismissed: DismissedJourneys
    private let now: () -> Date
    private let importService: ImportService
    /// Whether a found journey is matched to a stored trip by the photographs
    /// they share (ADR 2026-09-23 (d)). Off only for `-demo-discover`, whose
    /// invented photographs borrow the simulator's few asset ids in rotation:
    /// every demo journey holds the same ids, so one stored trip claimed all
    /// the others and the list offered nothing else (#178). A demo journey is
    /// still matched by its discovery key.
    private let matchesTripsByPhotographs: Bool

    /// Discovered journeys not yet imported, by key — hidden ones included, so
    /// one shown again can be opened.
    private(set) var detected: [String: DiscoveredJourney] = [:]
    /// Each found journey's cluster plan, made once by the scan off the main
    /// actor (Footprints ADR draft, Data 2). The card, the itinerary and the
    /// import all read this one plan.
    private(set) var plans: [String: ImportedTripPlan] = [:]
    /// Home's country, for the domestic-naming rule. From the device's region,
    /// never from a lookup (`JourneyNaming`).
    let homeCountryCode: String?
    private var namingTask: Task<Void, Never>?
    /// Journeys whose place `nameNow` is already asking about, so the queue in
    /// `startNaming` does not ask a second time.
    private var namingNow: Set<String> = []

    init(
        config: TrackingConfig,
        repository: TripRepository,
        source: ImportPhotoProviding,
        photoAccess: PhotoAccessProviding,
        geocoder: PlaceGeocoding? = nil,
        stopGeocoder: StopGeocoding? = nil,
        defaults: UserDefaults = .standard,
        homeCountryCode: String? = JourneyNameCache.deviceHomeCountryCode,
        matchesTripsByPhotographs: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.repository = repository
        provider = source
        self.photoAccess = photoAccess
        // Behind any stop naming, on the one throttle the app shares (#159).
        self.geocoder = geocoder ?? CLPlaceGeocoder(priority: .card, minIntervalS: config.geocode.minIntervalS)
        tripGeocoder = geocoder ?? CLPlaceGeocoder(priority: .tripFlag, minIntervalS: config.geocode.minIntervalS)
        nameCache = JourneyNameCache(defaults: defaults)
        previewNamer = stopGeocoder.map(PreviewStopNamer.init(geocoder:))
            ?? PreviewStopNamer(config: config.geocode)
        dismissed = DismissedJourneys(defaults: defaults)
        self.homeCountryCode = homeCountryCode
        self.matchesTripsByPhotographs = matchesTripsByPhotographs
        self.now = now
        importService = ImportService(repository: repository, config: config)
    }

    var isScanning: Bool { phase == .scanning }
    var isLimitedAccess: Bool { access == .limited }
    var hasJourneys: Bool { !journeys.isEmpty }

    func summary(forTrip tripId: String) -> JourneySummary? {
        journeys.first { $0.tripId == tripId }
    }

    // MARK: - Loading

    /// Stored trips instantly; a scan too, if the library may be read. Called
    /// on appear and after anything that changes the library or the trips.
    func refresh() async {
        access = photoAccess.readAccess
        loadTrips()
        switch access {
        case .granted, .limited: await discover()
        case .undetermined, .denied: phase = .ready
        }
    }

    /// The welcome card's button: ask, then scan.
    func requestAccessAndDiscover() async {
        access = await photoAccess.requestReadAccess()
        loadTrips()
        switch access {
        case .granted, .limited: await discover()
        case .undetermined, .denied: phase = .ready
        }
    }

    /// Reads every stored trip into a summary. Cheap: one read per trip.
    func loadTrips() {
        // The sample is not a journey anyone took (ADR 2026-09-28-sample-trip).
        let trips = (Stored.read("allTrips") { try repository.allTrips() } ?? []).filter { !$0.tripSource.isSample }
        var summaries: [JourneySummary] = []
        for trip in trips {
            guard let facts = Stored.read("journeyCardFacts", { try repository.journeyCardFacts(tripId: trip.id) })
            else { continue }
            summaries.append(summary(trip: trip, facts: facts))
        }
        // Discovered journeys that are still only in memory stay on the list.
        let pending = journeys.filter { !$0.isImported && detected[$0.id] != nil }
        journeys = (summaries + pending).sorted { $0.startedAt > $1.startedAt }
        startNaming()
    }

    /// Scans the library and adds every journey that is not already a trip.
    func discover() async {
        phase = .scanning
        let end = now()
        let start = Calendar.current.date(
            byAdding: .year, value: -config.discovery.lookbackYears, to: end
        ) ?? end
        let photos = await provider.photos(matching: .dateRange(from: start, to: end))
        // Home is estimated on device to decide what is "away", and that is all
        // it is used for: the estimate never leaves this function.
        // Off the main actor: with the country rule a scan is ~0.3 s per 50,000
        // photographs on a Mac (measured 2026-09-25, release), more on a phone,
        // and the scanning spinner must keep turning. The outlines are read for
        // this scan only (≈0.8 MB, released after); nothing loads at launch.
        // Unreadable → the country rule is off.
        let (detectionConfig, clustering) = (self.detectionConfig, ImportService.clustering(config))
        let (detection, scanned) = await Task.detached(priority: .userInitiated) {
            let detection = JourneyDetector.detect(
                photos: photos, config: detectionConfig, countries: CountryBoundaries.bundled()
            )
            let plans = detection.journeys.map { PhotoImportClusterer.plan(photos: $0.photos, config: clustering) }
            return (detection, Dictionary(zip(detection.journeys.map(\.key), plans)) { first, _ in first })
        }.value

        let hidden = dismissed.keys
        var found: [String: DiscoveredJourney] = [:]
        var fresh: [JourneySummary] = []
        var stillHidden: [JourneySummary] = []
        for journey in detection.journeys {
            if Stored.read("trip(discoveryKey:)", { try repository.trip(discoveryKey: journey.key) }) != nil { continue }
            // A trip made through the import sheet has no discovery key, so it
            // is matched by its photographs instead (Chiu 2026-09-23). It is
            // already on this list as a stored trip; offering the journey
            // beside it is what made two "Vietnam"s.
            guard let plan = scanned[journey.key], storedTrip(holding: plan) == nil else { continue }
            found[journey.key] = journey
            if hidden.contains(journey.key) {
                stillHidden.append(summary(journey: journey, plan: plan))
            } else {
                fresh.append(summary(journey: journey, plan: plan))
            }
        }
        detected = found
        plans = scanned.filter { found[$0.key] != nil }
        hiddenJourneys = stillHidden.sorted { $0.startedAt > $1.startedAt }
        let stored = journeys.filter(\.isImported)
        journeys = (stored + fresh).sorted { $0.startedAt > $1.startedAt }
        phase = .ready
        startNaming()
    }

    /// The stored trip these photographs already belong to, if any — unless
    /// this library's asset ids do not tell photographs apart.
    private func storedTrip(holding plan: ImportedTripPlan) -> String? {
        matchesTripsByPhotographs ? importService.existingTrip(plan: plan) : nil
    }

    // MARK: - Opening and hiding

    /// The trip to show for a card, importing the journey first if it never
    /// was. Returns nil when the import could not produce a trip.
    func open(_ summary: JourneySummary) async -> String? {
        if let tripId = summary.tripId { return tripId }
        guard let journey = detected[summary.id], let plan = plans[summary.id] else { return nil }
        // A trip may have been imported through the sheet since the scan.
        if let existing = storedTrip(holding: plan) {
            detected[journey.key] = nil
            plans[journey.key] = nil
            loadTrips()
            return existing
        }
        openingId = summary.id
        openFailure = nil
        defer { openingId = nil }
        do {
            // No title: the trip is stored unnamed and `TripTitle` calls it by
            // its place on every screen, whenever the lookup answers. Passing
            // the card's headline froze the trip at whatever the lookup had
            // reached at the tap — "September 2026", for good (#165).
            let tripId = try await importService.importTrip(
                title: nil, photos: journey.photos, discoveryKey: journey.key, plan: plan
            )
            nameCache.setSinglePlace(summary.isSinglePlace, for: journey.key)
            // What the preview already learnt about each stop, so S3 does not
            // ask Apple a second time (Data 3: one lookup per stop, ever).
            if let detail = Stored.read("detail", { try repository.detail(tripId: tripId) }) {
                previewNamer.write(to: detail.stops, repository: repository)
            }
            // Roads arrive when they arrive, exactly as after the import sheet
            // (2026-08-15); the trip is viewable now.
            RouteMatchCoordinator.shared.start(
                tripId: tripId,
                service: RouteMatchService(repository: repository, matching: config.matching)
            )
            PhotoAnalysisCoordinator.shared.start(
                tripId: tripId, repository: repository, config: config.photoAnalysis
            )
            detected[journey.key] = nil
            plans[journey.key] = nil
            nameNow(summary)
            loadTrips()
            return tripId
        } catch ImportService.ImportError.notEnoughGeotaggedPhotos {
            openFailure = .notATrip
            return nil
        } catch {
            KamomeLog.recap.error("discovered journey could not be imported: \(error)")
            openFailure = .saveFailed
            return nil
        }
    }

    /// The screen has shown `openFailure`.
    func acknowledgeOpenFailure() {
        openFailure = nil
    }

    /// Hides a discovered journey. Remembered, so a rescan does not bring it
    /// back; it moves to the hidden row, where `unhide` returns it. Stored
    /// trips are deleted through `delete` instead.
    func hide(_ summary: JourneySummary) {
        guard !summary.isImported else { return }
        dismissed.dismiss(summary.id)
        journeys.removeAll { $0.id == summary.id }
        hiddenJourneys = (hiddenJourneys + [summary]).sorted { $0.startedAt > $1.startedAt }
    }

    /// Shows a hidden journey again, where it sits by date (#167). A hidden
    /// journey was never named; it is queued for its one lookup now.
    func unhide(_ summary: JourneySummary) {
        guard let index = hiddenJourneys.firstIndex(where: { $0.id == summary.id }) else { return }
        dismissed.restore(summary.id)
        journeys = (journeys + [hiddenJourneys.remove(at: index)]).sorted { $0.startedAt > $1.startedAt }
        startNaming()
    }

    /// Deletes a stored trip and its films. The journey may be rediscovered on
    /// the next scan; that is the honest outcome of deleting the trip and not
    /// the photographs.
    func delete(_ summary: JourneySummary) {
        guard let tripId = summary.tripId else { return }
        guard TripDeletion.delete(tripId: tripId, repository: repository) else { return }
        journeys.removeAll { $0.id == summary.id }
    }

    /// Selected Photos: grow the selection, then look again — the selection
    /// *is* the library discovery can see.
    func selectMorePhotos() {
        photoAccess.presentLimitedLibraryPicker { [weak self] in
            Task { await self?.refresh() }
        }
    }

    // MARK: - Naming

    /// Looks up the place of a journey that has just become a trip, ahead of
    /// the cards, and finishes even if this screen has gone: the trip is
    /// stored unnamed (`open`), so Home shows its date until this answers. The
    /// same single lookup the queue would make — the journey's busiest stop —
    /// only sooner, through the shared gate at a new trip's priority;
    /// `namingNow` keeps the queue from making it twice.
    private func nameNow(_ summary: JourneySummary) {
        guard nameCache.place(for: summary.id) == nil,
              let lat = summary.nameLookupLat, let lon = summary.nameLookupLon
        else { return }
        let (id, geocoder, cache) = (summary.id, tripGeocoder, nameCache)
        namingNow.insert(id)
        Task { [weak self] in
            if let place = await geocoder.place(lat: lat, lon: lon) {
                cache.store(place, for: id)
            } else {
                KamomeLog.geocode.notice("journey naming produced no place for \(id, privacy: .public)")
            }
            self?.namingNow.remove(id)
            self?.loadTrips()
        }
    }

    /// Names every journey that has none, one lookup at a time. Restarted
    /// whenever the list changes; cached places are applied synchronously in
    /// `summary(...)`, so only an unknown place costs a lookup.
    ///
    /// **One lookup per journey, and nothing else.** Each sends that journey's
    /// busiest stop to Apple — the recipient `privacy_intro` names for place
    /// names. Home is never looked up (`JourneyNaming`).
    private func startNaming() {
        namingTask?.cancel()
        let pending = journeys.filter { $0.name == nil && $0.nameLookupLat != nil && !namingNow.contains($0.id) }
        guard !pending.isEmpty else { return }
        let interval = config.geocode.minIntervalS
        namingTask = Task { [weak self] in
            guard let self else { return }
            for summary in pending {
                guard !Task.isCancelled, let lat = summary.nameLookupLat, let lon = summary.nameLookupLon else { return }
                if let place = await geocoder.place(lat: lat, lon: lon) {
                    nameCache.store(place, for: summary.id)
                    if let index = journeys.firstIndex(where: { $0.id == summary.id }) {
                        journeys[index].name = JourneyNaming.name(
                            place: place, homeCountryCode: homeCountryCode, isSinglePlace: summary.isSinglePlace
                        )
                        journeys[index].countryCode = place.countryCode
                        journeys[index].countryName = place.country
                    }
                } else {
                    KamomeLog.geocode.notice("journey naming produced no place for \(summary.id, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
