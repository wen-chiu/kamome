import Foundation
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer
import Observation

/// How a stored trip or a detected journey becomes a card. Split out of
/// `JourneyDiscoveryModel` (arch review 2026-09-26, round 2) when `UI/` came
/// under SwiftLint: the class body was 281 lines against 250. Moved as written.
extension JourneyDiscoveryModel {
    func summary(trip: TripRecord, facts: TripRepository.JourneyCardFacts) -> JourneySummary {
        let id = trip.discoveryKey ?? trip.id
        let stats = TripStats.from(jsonString: trip.statsJson)
        var extentM = 0.0
        if let span = facts.stopSpan {
            extentM = PhotoImportClusterer.haversineMeters(span.minLat, span.minLon, span.maxLat, span.maxLon)
        }
        let isSinglePlace = extentM < config.discovery.singlePlaceExtentM
        let place = nameCache.place(for: id)
        return JourneySummary(
            id: id,
            tripId: trip.id,
            discoveryKey: trip.discoveryKey,
            name: nameCache.name(for: id, homeCountryCode: homeCountryCode, isSinglePlace: isSinglePlace),
            fallbackTitle: trip.title,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt ?? trip.startedAt,
            photoCount: facts.photos.count,
            stopCount: facts.stopCount,
            coverAssetIds: PhotoCoverSelector.select(
                facts.photos.map { PhotoCoverSelector.Candidate(assetId: $0.phAssetId, isHighlight: $0.isHighlight == 1) },
                count: config.discovery.coverPhotos
            ),
            distanceM: groundDistance(trip: trip, stats: stats),
            legModes: facts.legModes,
            // A stop stored before ADR 2026-09-23 may be "named" by its own
            // coordinate. `StopNamer` renames it when Trip Detail next opens;
            // until then the timeline leaves it out rather than print a
            // coordinate that reads as a bug (Chiu, 2026-09-23).
            milestones: facts.stopNames.filter { !StopDisplayName.isCoordinate($0) },
            provenance: trip.tripSource.isReconstructed ? .fromPhotos : .recorded,
            filmCount: facts.filmCount,
            nameLookupLat: facts.nameLookupLat,
            nameLookupLon: facts.nameLookupLon,
            isSinglePlace: isSinglePlace,
            countryCode: place?.countryCode,
            countryName: place?.country
        )
    }

    /// Kilometres on the ground (`LegLength.groundMeters`). A recording's own
    /// stats are its measured distance; a trip rebuilt from photographs is
    /// measured along its routed legs, flights left out.
    func groundDistance(trip: TripRecord, stats: TripStats?) -> Double? {
        if !trip.tripSource.isReconstructed, let measured = stats?.distanceM { return measured }
        guard let detail = Stored.read("detail", { try repository.detail(tripId: trip.id) }) else { return nil }
        return LegLength.groundMeters(detail.segments)
    }

    func summary(journey: DiscoveredJourney) -> JourneySummary {
        let plan = PhotoImportClusterer.plan(photos: journey.photos, config: ImportClusteringConfig(
            stopRadiusM: config.photoImport.stopRadiusM,
            stopSplitGapS: config.photoImport.stopSplitGapS,
            minPhotosPerStop: config.photoImport.minPhotosPerStop
        ))
        let busiest = plan.stops.max { $0.photoAssetIds.count < $1.photoAssetIds.count }
        let modes = plan.legs.map { ImportService.mode(for: $0, config: config).rawValue }
        let isSinglePlace = journey.extentM < config.discovery.singlePlaceExtentM
        let place = nameCache.place(for: journey.key)
        return JourneySummary(
            id: journey.key,
            tripId: nil,
            discoveryKey: journey.key,
            name: nameCache.name(
                for: journey.key, homeCountryCode: homeCountryCode, isSinglePlace: isSinglePlace
            ),
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
            // **A stop, or nothing.** Chiu's §0 exception for Apple is scoped to
            // stop points (ADR 2026-09-16, PR #72: 「停留點一定只能送 apple 去問」).
            // This used to fall back to the centroid of all the journey's photos
            // when no cluster became a stop — an average position that is not a
            // stop, so outside the exception. A journey with no stop is simply not
            // looked up, and keeps its month title.
            nameLookupLat: busiest?.lat,
            nameLookupLon: busiest?.lon,
            isSinglePlace: isSinglePlace,
            countryCode: place?.countryCode,
            countryName: place?.country
        )
    }

    /// "March 2026" — what a journey is called until its place is known.
    static func monthTitle(for timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
