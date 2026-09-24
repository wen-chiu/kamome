import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence

/// Which photographs the film shows (ADR 2026-09-24), split out of
/// `RecapComposer` for its size budget: the inputs read from a trip, the stop
/// selection, and each stop's deck at its final size. The export, the photo
/// picker's preview and the desk harnesses all come through here.
extension RecapComposer {
    /// One stop's deck at its final size: the allocation, lifted by the
    /// person's highlights up to `highlightMaxPhotos`, picked across the whole
    /// visit. This used to be `prefix(allocated)` of an eight-photo spread, which
    /// could only ever reach the first third of a visit (Chiu 2026-09-24).
    static func deckPhotos(
        _ candidates: [PhotoRef], allocated: Int,
        highlightedAssets: Set<String>, highlightMaxPhotos: Int
    ) -> [PhotoRef] {
        let marked = candidates.map { ref -> (ref: PhotoRef, isHighlight: Bool) in
            guard case let .asset(id) = ref else { return (ref, false) }
            return (ref, highlightedAssets.contains(id))
        }
        let count = PhotoDeckSelector.deckCount(
            allocated: allocated, highlights: marked.filter(\.isHighlight).count,
            highlightCap: highlightMaxPhotos
        )
        return PhotoDeckSelector.pick(marked, count: count)
    }

    /// What the film's photo selection reads from one trip (ADR 2026-09-24).
    /// Photographs the person left out are gone from all of it: never a
    /// candidate, and not counted towards their stop.
    struct PhotoInputs {
        /// Stop id → the stop's candidates, in time order.
        var byStop: [String: [PhotoRef]] = [:]
        /// Starred assets — a Photos favourite at import, or a star in Kamome.
        var highlighted: Set<String> = []
        /// Stop id → photographs at the stop (`StopPhotoAllocator.Signal.photoCount`).
        var rawCounts: [String: Int] = [:]
        /// Stop id → starred photographs at the stop; any at all keeps the stop.
        var starredCounts: [String: Int] = [:]
    }

    /// Builds `PhotoInputs` — the one place the export, the photo picker's
    /// preview and the desk harnesses read a trip's photographs from, so all
    /// three select exactly the same decks.
    static func photoInputs(detail: TripRepository.TripDetail) -> PhotoInputs {
        var inputs = PhotoInputs()
        let usable = detail.photos
            .filter { $0.isExcluded == 0 }
            // Asset id breaks a timestamp tie, so a burst lands in the same
            // order on every export.
            .sorted { ($0.takenAt ?? 0, $0.phAssetId) < ($1.takenAt ?? 0, $1.phAssetId) }
        for photo in usable {
            guard let stopId = photo.stopId else { continue }
            inputs.byStop[stopId, default: []].append(.asset(photo.phAssetId))
            inputs.rawCounts[stopId, default: 0] += 1
            if photo.isHighlight != 0 {
                inputs.highlighted.insert(photo.phAssetId)
                inputs.starredCounts[stopId, default: 0] += 1
            }
        }
        return inputs
    }

    /// The stops the film presents, each with its final deck, in trip order —
    /// selection, allocation and the deck pick in one pass. `trip` builds the
    /// film from it; `filmDecks` shows it before the film exists.
    static func deckPlan(
        stops: [StopRecord], inputs: PhotoInputs, highlightMaxPhotos: Int, weighting: TrackingConfig.Export?
    ) -> [(stop: StopRecord, photos: [PhotoRef])] {
        let selection = select(stops: stops, photosByStop: inputs.byStop,
                               rawPhotoCounts: inputs.rawCounts, favoriteCounts: inputs.starredCounts,
                               weighting: weighting)
        return selection.kept.map { stop in
            var photos = inputs.byStop[stop.id] ?? []
            if let allocated = selection.allocation[stop.id] {
                photos = deckPhotos(photos, allocated: allocated,
                                    highlightedAssets: inputs.highlighted, highlightMaxPhotos: highlightMaxPhotos)
            }
            // Stop weighting: an independent legacy flag, shipping `false`, that
            // survives the mode migration by explicit decision (HANDOFF). Measured
            // as having no reachable effect beyond what the modes already do.
            if let weighting, weighting.stopWeightingEnabled {
                let raw = inputs.rawCounts[stop.id] ?? photos.count
                let dwell = (stop.departedAt ?? stop.arrivedAt) - stop.arrivedAt
                if StopWeighting.classify(photoCount: raw, dwellS: dwell, config: weighting) == .waypoint {
                    photos = []
                }
            }
            return (stop, photos)
        }
    }

    /// Stop id → the asset ids the film will show at that stop, for every stop
    /// the film presents — **the export's own selection**, read before a frame
    /// is rendered, so the photo picker can say which photographs are in (ADR
    /// 2026-09-24). Same records (`filmRecords`: the film ends at the
    /// destination), same inputs, same plan as `RecapExportJob.compose`.
    static func filmDecks(detail: TripRepository.TripDetail, config: TrackingConfig) -> [String: [String]] {
        let film = filmRecords(
            segments: detail.segments, stops: detail.stops,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM,
            homeRadiusM: config.discovery.awayRadiusM
        )
        let plan = deckPlan(
            stops: film.stops, inputs: photoInputs(detail: detail),
            highlightMaxPhotos: config.photoImport.deckHighlightMaxPhotos, weighting: config.export
        )
        var decks: [String: [String]] = [:]
        for (stop, photos) in plan {
            decks[stop.id] = photos.compactMap { ref in
                if case let .asset(id) = ref { return id }
                return nil
            }
        }
        return decks
    }

    /// Which stops the film presents, and how many photographs each shows.
    ///
    /// **One switch, one decision.** This used to be three conditionals over three
    /// booleans, each carrying a negation of the others. Exhaustive with no
    /// `default:` on purpose: adding a `RecapMode` case must break the build here
    /// rather than fall silently into an existing branch.
    private static func select(
        stops: [StopRecord],
        photosByStop: [String: [PhotoRef]],
        rawPhotoCounts: [String: Int],
        favoriteCounts: [String: Int],
        weighting: TrackingConfig.Export?
    ) -> (kept: [StopRecord], allocation: [String: Int]) {
        guard let weighting else { return (stops, [:]) }
        let signals = stops.map { stop in
            StopPhotoAllocator.Signal(
                photoCount: rawPhotoCounts[stop.id] ?? (photosByStop[stop.id]?.count ?? 0),
                favoriteCount: favoriteCounts[stop.id] ?? 0
            )
        }
        var allocation: [String: Int] = [:]
        switch weighting.recapMode {
        case .highlight:
            // A skipped stop leaves the film entirely — no pin, no name, no pause,
            // no park beat.
            // The trip earns its stop count from its own size (Chiu 2026-08-14).
            // This used to pass `totalDurationMaxS`, which is why every trip
            // presented the same 8 stops whether it had 10 or 65: the duration
            // ceiling was the same for all of them.
            let tiers = StopPhotoAllocator.triage(signals, config: weighting)
            let kept = zip(stops, tiers).compactMap { stop, tier -> StopRecord? in
                guard let tier else { return nil }
                allocation[stop.id] = tier
                return stop
            }
            return (kept, allocation)
        case .full:
            // Every stop survives; rank decides how many photographs it shows.
            let counts = StopPhotoAllocator.allocate(signals, config: weighting)
            for (stop, count) in zip(stops, counts) { allocation[stop.id] = count }
            return (stops, allocation)
        }
    }
}
