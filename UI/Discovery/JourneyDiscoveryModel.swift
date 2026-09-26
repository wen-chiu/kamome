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
    /// Set while a discovered journey is being imported on the way to its screen.
    private(set) var openingId: String?

    let config: TrackingConfig
    let repository: TripRepository
    private let provider: ImportPhotoProviding
    private let photoAccess: PhotoAccessProviding
    private let geocoder: PlaceGeocoding
    let nameCache: JourneyNameCache
    private let dismissed: DismissedJourneys
    private let now: () -> Date
    private let importService: ImportService

    /// Discovered journeys not yet imported, by key.
    private var detected: [String: DiscoveredJourney] = [:]
    /// Home's country, for the domestic-naming rule. From the device's region,
    /// never from a lookup (`JourneyNaming`).
    let homeCountryCode: String?
    private var namingTask: Task<Void, Never>?

    init(
        config: TrackingConfig,
        repository: TripRepository,
        source: ImportPhotoProviding,
        photoAccess: PhotoAccessProviding,
        geocoder: PlaceGeocoding = CLPlaceGeocoder(),
        defaults: UserDefaults = .standard,
        homeCountryCode: String? = JourneyNameCache.deviceHomeCountryCode,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.repository = repository
        provider = source
        self.photoAccess = photoAccess
        self.geocoder = geocoder
        nameCache = JourneyNameCache(defaults: defaults)
        dismissed = DismissedJourneys(defaults: defaults)
        self.homeCountryCode = homeCountryCode
        self.now = now
        importService = ImportService(repository: repository, config: config)
    }

    // MARK: - What the screen draws

    var sections: [JourneyYearSection] {
        let grouped = Dictionary(grouping: journeys, by: \.year)
        return grouped.keys.sorted(by: >).map { year in
            JourneyYearSection(year: year, journeys: grouped[year] ?? [])
        }
    }

    /// Which visit to its country each journey was, by id (`JourneyChronicle`).
    var visits: [String: JourneyChronicle.Visit] {
        JourneyChronicle.visits(journeys, homeCountryCode: homeCountryCode)
    }

    /// Days at home before each journey began, keyed by that (newer) journey's
    /// id — the row sits under it on screen, between it and the one before it.
    /// Empty when `discovery.show_home_gaps` is off.
    var homeGaps: [String: Int] {
        guard config.discovery.showHomeGaps else { return [:] }
        var gaps: [String: Int] = [:]
        for (newer, older) in zip(journeys, journeys.dropFirst()) {
            if let days = JourneyChronicle.homeDays(after: older, before: newer) { gaps[newer.id] = days }
        }
        return gaps
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
        let trips = Stored.read("allTrips") { try repository.allTrips() } ?? []
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
        let detectionConfig = self.detectionConfig
        let detection = await Task.detached(priority: .userInitiated) {
            JourneyDetector.detect(photos: photos, config: detectionConfig, countries: CountryBoundaries.bundled())
        }.value

        let hidden = dismissed.keys
        var found: [String: DiscoveredJourney] = [:]
        var fresh: [JourneySummary] = []
        for journey in detection.journeys where !hidden.contains(journey.key) {
            if Stored.read("trip(discoveryKey:)", { try repository.trip(discoveryKey: journey.key) }) != nil { continue }
            // A trip made through the import sheet has no discovery key, so it
            // is matched by its photographs instead (Chiu 2026-09-23). It is
            // already on this list as a stored trip; offering the journey
            // beside it is what made two "Vietnam"s.
            if importService.existingTrip(for: journey.photos) != nil { continue }
            found[journey.key] = journey
            fresh.append(summary(journey: journey))
        }
        detected = found
        let stored = journeys.filter(\.isImported)
        journeys = (stored + fresh).sorted { $0.startedAt > $1.startedAt }
        phase = .ready
        startNaming()
    }

    // MARK: - Opening and hiding

    /// The trip to show for a card, importing the journey first if it never
    /// was. Returns nil when the import could not produce a trip.
    func open(_ summary: JourneySummary) async -> String? {
        if let tripId = summary.tripId { return tripId }
        guard let journey = detected[summary.id] else { return nil }
        // A trip may have been imported through the sheet since the scan.
        if let existing = importService.existingTrip(for: journey.photos) {
            detected[journey.key] = nil
            loadTrips()
            return existing
        }
        openingId = summary.id
        defer { openingId = nil }
        do {
            let tripId = try await importService.importTrip(
                title: summary.headline, photos: journey.photos, discoveryKey: journey.key
            )
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
            loadTrips()
            return tripId
        } catch {
            KamomeLog.recap.error("discovered journey could not be imported: \(error)")
            return nil
        }
    }

    /// Hides a discovered journey. Remembered, so a rescan does not bring it
    /// back. Stored trips are deleted through `delete` instead.
    func hide(_ summary: JourneySummary) {
        guard !summary.isImported else { return }
        dismissed.dismiss(summary.id)
        detected[summary.id] = nil
        journeys.removeAll { $0.id == summary.id }
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

    private var detectionConfig: JourneyDetectionConfig {
        JourneyDetectionConfig(
            homeCellDeg: config.discovery.homeCellDeg,
            awayRadiusM: config.discovery.awayRadiusM,
            journeyGapS: config.discovery.journeyGapS,
            minPhotos: config.discovery.minPhotos,
            homecomingMinJumpM: config.discovery.homecomingMinJumpM,
            countryCoastBufferM: config.discovery.countryCoastBufferM
        )
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
        let pending = journeys.filter { $0.name == nil && $0.nameLookupLat != nil }
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
