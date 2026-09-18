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

    private let config: TrackingConfig
    private let repository: TripRepository
    private let provider: ImportPhotoProviding
    private let photoAccess: PhotoAccessProviding
    private let geocoder: PlaceGeocoding
    private let nameCache: JourneyNameCache
    private let dismissed: DismissedJourneys
    private let now: () -> Date
    private let importService: ImportService

    /// Discovered journeys not yet imported, by key.
    private var detected: [String: DiscoveredJourney] = [:]
    private var homeLookup: (lat: Double, lon: Double)?
    private var homePlace: PlaceName?
    private var namingTask: Task<Void, Never>?

    init(
        config: TrackingConfig,
        repository: TripRepository,
        source: ImportPhotoProviding,
        photoAccess: PhotoAccessProviding,
        geocoder: PlaceGeocoding = CLPlaceGeocoder(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.repository = repository
        provider = source
        self.photoAccess = photoAccess
        self.geocoder = geocoder
        nameCache = JourneyNameCache(defaults: defaults)
        dismissed = DismissedJourneys(defaults: defaults)
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
        let trips = (try? repository.allTrips()) ?? []
        var summaries: [JourneySummary] = []
        for trip in trips {
            guard let facts = try? repository.journeyCardFacts(tripId: trip.id) else { continue }
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
        let detection = JourneyDetector.detect(photos: photos, config: detectionConfig)
        homeLookup = detection.home.map { ($0.lat, $0.lon) }

        let hidden = dismissed.keys
        var found: [String: DiscoveredJourney] = [:]
        var fresh: [JourneySummary] = []
        for journey in detection.journeys where !hidden.contains(journey.key) {
            if (try? repository.trip(discoveryKey: journey.key)) != nil { continue }
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
        let films = (try? repository.deleteTrip(tripId: tripId)) ?? []
        for film in films { FilmStore.deleteFile(relativePath: film.relativePath) }
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
            minPhotos: config.discovery.minPhotos
        )
    }

    /// Names every journey that has none, one lookup at a time, oldest request
    /// last. Restarted whenever the list changes; cached names are applied
    /// synchronously in `summary(...)` so only unknown places cost a lookup.
    private func startNaming() {
        namingTask?.cancel()
        let pending = journeys.filter { $0.name == nil && $0.nameLookupLat != nil }
        guard !pending.isEmpty else { return }
        let interval = config.geocode.minIntervalS
        namingTask = Task { [weak self] in
            guard let self else { return }
            if homePlace == nil, let home = homeLookup {
                if let cached = nameCache.home() {
                    homePlace = cached
                } else if let looked = await geocoder.place(lat: home.lat, lon: home.lon) {
                    homePlace = looked
                    nameCache.storeHome(looked)
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
            for summary in pending {
                guard !Task.isCancelled, let lat = summary.nameLookupLat, let lon = summary.nameLookupLon else { return }
                if let place = await geocoder.place(lat: lat, lon: lon) {
                    nameCache.store(place, for: summary.id)
                    if let index = journeys.firstIndex(where: { $0.id == summary.id }) {
                        journeys[index].name = JourneyNaming.name(
                            place: place, home: homePlace, isSinglePlace: summary.isSinglePlace
                        )
                    }
                } else {
                    KamomeLog.geocode.notice("journey naming produced no place for \(summary.id, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // MARK: - Summaries

    private func summary(trip: TripRecord, facts: TripRepository.JourneyCardFacts) -> JourneySummary {
        let id = trip.discoveryKey ?? trip.id
        let stats = TripStats.from(jsonString: trip.statsJson)
        var extentM = 0.0
        if let span = facts.stopSpan {
            extentM = PhotoImportClusterer.haversineMeters(span.minLat, span.minLon, span.maxLat, span.maxLon)
        }
        let isSinglePlace = extentM < config.discovery.singlePlaceExtentM
        return JourneySummary(
            id: id,
            tripId: trip.id,
            discoveryKey: trip.discoveryKey,
            name: nameCache.name(for: id, isSinglePlace: isSinglePlace),
            fallbackTitle: trip.title,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt ?? trip.startedAt,
            photoCount: facts.photos.count,
            stopCount: facts.stopCount,
            coverAssetIds: PhotoCoverSelector.select(
                facts.photos.map { PhotoCoverSelector.Candidate(assetId: $0.phAssetId, isHighlight: $0.isHighlight == 1) },
                count: config.discovery.coverPhotos
            ),
            distanceM: stats?.distanceM,
            legModes: facts.legModes,
            milestones: facts.stopNames,
            provenance: trip.tripSource.isReconstructed ? .fromPhotos : .recorded,
            filmCount: facts.filmCount,
            nameLookupLat: facts.nameLookupLat,
            nameLookupLon: facts.nameLookupLon,
            isSinglePlace: isSinglePlace
        )
    }

    private func summary(journey: DiscoveredJourney) -> JourneySummary {
        let plan = PhotoImportClusterer.plan(photos: journey.photos, config: ImportClusteringConfig(
            stopRadiusM: config.photoImport.stopRadiusM,
            stopSplitGapS: config.photoImport.stopSplitGapS,
            minPhotosPerStop: config.photoImport.minPhotosPerStop
        ))
        let busiest = plan.stops.max { $0.photoAssetIds.count < $1.photoAssetIds.count }
        let modes = plan.legs.map { ImportService.mode(for: $0, config: config).rawValue }
        let isSinglePlace = journey.extentM < config.discovery.singlePlaceExtentM
        return JourneySummary(
            id: journey.key,
            tripId: nil,
            discoveryKey: journey.key,
            name: nameCache.name(for: journey.key, isSinglePlace: isSinglePlace),
            fallbackTitle: Self.monthTitle(for: journey.startedAt),
            startedAt: journey.startedAt,
            endedAt: journey.endedAt,
            photoCount: journey.photoCount,
            stopCount: plan.stops.count,
            coverAssetIds: PhotoCoverSelector.select(
                journey.photos.map { PhotoCoverSelector.Candidate(assetId: $0.assetId, isHighlight: $0.isFavorite) },
                count: config.discovery.coverPhotos
            ),
            distanceM: nil,
            legModes: modes,
            // A journey nobody has opened has no geocoded stops, so it has no
            // milestones to name — the entry says how many places instead.
            milestones: [],
            provenance: .fromPhotos,
            filmCount: 0,
            nameLookupLat: busiest?.lat ?? journey.centroidLat,
            nameLookupLon: busiest?.lon ?? journey.centroidLon,
            isSinglePlace: isSinglePlace
        )
    }

    /// "March 2026" — what a journey is called until its place is known.
    static func monthTitle(for timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
