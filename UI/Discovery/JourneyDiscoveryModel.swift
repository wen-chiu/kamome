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
    let dismissed: DismissedJourneys
    private let now: () -> Date
    private let importService: ImportService
    /// Whether a found journey is matched to a stored trip by the photographs
    /// they share (ADR 2026-09-23 (d)). Off only for `-demo-discover`, whose
    /// invented photographs borrow the simulator's few asset ids in rotation:
    /// every demo journey holds the same ids, so one stored trip claimed all
    /// the others and the list offered nothing else (#178). A demo journey is
    /// still matched by its discovery key.
    let matchesTripsByPhotographs: Bool

    /// Every journey the last scan found, by key — hidden ones, and ones a
    /// stored trip now holds, included. The list leaves out the stored ones
    /// each time it is read (`unstoredKeys(trips:)`), so a trip deleted in Journeys
    /// gives its journey back without a rescan (#262).
    private(set) var detected: [String: DiscoveredJourney] = [:]
    /// Each found journey's cluster plan, made once by the scan off the main
    /// actor (Footprints ADR draft, Data 2). The card, the itinerary and the
    /// import all read this one plan.
    private(set) var plans: [String: ImportedTripPlan] = [:]
    /// The found journeys no stored trip holds, and the ids of the stored
    /// trips that set was worked out against. Matching by photographs is one
    /// read per journey, so it is redone only when the trips change (#262).
    private var matchedUnstored: Set<String> = []
    private var matchedAgainst: Set<String>?
    /// The keys hidden this scan: hidden records matched to this scan's
    /// journeys by their photographs (#170). Before a scan, the stored keys.
    private var hiddenKeys: Set<String>
    /// Home's country, for the domestic-naming rule. From the device's region,
    /// never from a lookup (`JourneyNaming`).
    let homeCountryCode: String?
    private var namingTask: Task<Void, Never>?
    /// Journeys whose place is being asked about right now, by `nameNow` or
    /// by the queue, so a queue restarted mid-lookup does not ask again.
    private var namingNow: Set<String> = []
    /// Journeys whose lookup answered nothing this session. Not asked again
    /// until the person pulls to refresh, and no longer drawn as naming (#263).
    private(set) var unanswered: Set<String> = []

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
        let dismissed = DismissedJourneys(defaults: defaults)
        self.dismissed = dismissed
        hiddenKeys = dismissed.keys
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
    /// on first appearance, on pull-to-refresh and after the Selected Photos
    /// picker: each is the person asking, so a journey whose name lookup
    /// answered nothing earlier is asked once more (#263).
    func refresh() async {
        unanswered = []
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

    /// Reads every stored trip into a summary, and lays the found journeys no
    /// trip holds beside them. Cheap: one read per trip, plus one per found
    /// journey when the trips have changed since the last read.
    ///
    /// Called each time Footprints is shown, so a trip imported or deleted in
    /// Journeys is reflected without a rescan (#262): a journey imported
    /// through the sheet is not listed twice, and one whose trip was deleted
    /// is offered again.
    func loadTrips() {
        // The sample is not a journey anyone took (ADR 2026-09-28-sample-trip).
        let trips = (Stored.read("allTrips") { try repository.allTrips() } ?? []).filter { !$0.tripSource.isSample }
        var summaries: [JourneySummary] = []
        for trip in trips {
            guard let facts = Stored.read("journeyCardFacts", { try repository.journeyCardFacts(tripId: trip.id) })
            else { continue }
            summaries.append(summary(trip: trip, facts: facts))
        }
        let hidden = hiddenKeys
        var shown: [JourneySummary] = []
        var stillHidden: [JourneySummary] = []
        for key in unstoredKeys(trips: trips) {
            guard let journey = detected[key], let plan = plans[key] else { continue }
            if hidden.contains(key) {
                stillHidden.append(summary(journey: journey, plan: plan))
            } else {
                shown.append(summary(journey: journey, plan: plan))
            }
        }
        hiddenJourneys = stillHidden.sorted { $0.startedAt > $1.startedAt }
        journeys = (summaries + shown).sorted { $0.startedAt > $1.startedAt }
        startNaming()
    }

    /// The found journeys no stored trip holds: not by its discovery key and,
    /// for a trip made through the import sheet, which has none, not by the
    /// photographs they share (Chiu 2026-09-23 — offering the journey beside
    /// it is what made two "Vietnam"s).
    private func unstoredKeys(trips: [TripRecord]) -> Set<String> {
        let tripIds = Set(trips.map(\.id))
        guard tripIds != matchedAgainst else { return matchedUnstored }
        let keys = Set(trips.compactMap(\.discoveryKey))
        matchedUnstored = Set(detected.keys.filter { key in
            guard !keys.contains(key), let plan = plans[key] else { return false }
            return storedTrip(holding: plan) == nil
        })
        matchedAgainst = tripIds
        return matchedUnstored
    }

    /// Scans the library and adds every journey that is not already a trip.
    func discover() async {
        phase = .scanning
        let end = now()
        let start = Calendar.current.date(
            byAdding: .year, value: -config.discovery.lookbackYears, to: end
        ) ?? end
        let photos = await provider.photos(matching: .dateRange(from: start, to: end))
        let (detection, scanned) = await Self.detect(
            photos, config: detectionConfig, clustering: ImportService.clustering(config)
        )

        // Every journey is kept, stored or not; `loadTrips` leaves out the ones
        // a trip holds, against the trips as they are now.
        detected = Dictionary(detection.journeys.map { ($0.key, $0) }) { first, _ in first }
        plans = scanned
        matchedAgainst = nil
        hiddenKeys = reconciledHiddenKeys()
        loadTrips()
        phase = .ready
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
            // The journey stays in `detected`: should the trip be deleted in
            // Journeys, the list offers the journey again (#262).
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
        // Its photographs too, so it stays hidden when its key moves (#170) —
        // unless this library's asset ids do not tell photographs apart.
        let assetIds = matchesTripsByPhotographs ? detected[summary.id]?.photos.map(\.assetId) ?? [] : []
        dismissed.dismiss(summary.id, assetIds: assetIds)
        hiddenKeys.insert(summary.id)
        journeys.removeAll { $0.id == summary.id }
        hiddenJourneys = (hiddenJourneys + [summary]).sorted { $0.startedAt > $1.startedAt }
    }

    /// Shows a hidden journey again, where it sits by date (#167). A hidden
    /// journey was never named; it is queued for its one lookup now.
    func unhide(_ summary: JourneySummary) {
        guard let index = hiddenJourneys.firstIndex(where: { $0.id == summary.id }) else { return }
        dismissed.restore(summary.id)
        hiddenKeys.remove(summary.id)
        journeys = (journeys + [hiddenJourneys.remove(at: index)]).sorted { $0.startedAt > $1.startedAt }
        startNaming()
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
                self?.unanswered.insert(id)
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
    /// names. Home is never looked up (`JourneyNaming`). A lookup that answers
    /// nothing is not repeated this session (#263): the list is read again
    /// every time Footprints is shown, and it used to ask again every time.
    private func startNaming() {
        namingTask?.cancel()
        let pending = journeys.filter { awaitsName($0) && !namingNow.contains($0.id) }
        guard !pending.isEmpty else { return }
        let interval = config.geocode.minIntervalS
        namingTask = Task { [weak self] in
            guard let self else { return }
            for summary in pending {
                guard !Task.isCancelled, let lat = summary.nameLookupLat, let lon = summary.nameLookupLon else { return }
                namingNow.insert(summary.id)
                let answer = await geocoder.place(lat: lat, lon: lon)
                namingNow.remove(summary.id)
                if let place = answer {
                    nameCache.store(place, for: summary.id)
                    if let index = journeys.firstIndex(where: { $0.id == summary.id }) {
                        journeys[index].name = JourneyNaming.name(
                            place: place, homeCountryCode: homeCountryCode, isSinglePlace: summary.isSinglePlace
                        )
                        journeys[index].countryCode = place.countryCode
                        journeys[index].countryName = place.localizedCountry()
                    }
                } else {
                    KamomeLog.geocode.notice("journey naming produced no place for \(summary.id, privacy: .public)")
                    unanswered.insert(summary.id)
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
