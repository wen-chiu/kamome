@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence

/// Split out of `RecapDemoFilmTests.importedRecap` (lint length only, Chiu
/// 2026-08-07).
extension RecapDemoFilmTests {
    /// What `stopPhotoSelections` computes per stop — grouped so the per-stop
    /// dictionaries travel together instead of as a tuple.
    struct StopPhotoSelections {
        let photosByStop: [String: [PhotoRef]]
        let highlighted: Set<String>
        let rawPhotoCounts: [String: Int]
        let favoriteCounts: [String: Int]
    }

    /// **The app's own selection input** (`RecapComposer.photoCandidates`): every
    /// stop's photographs in time order plus the marked ones; the composer picks
    /// each deck after allocation. This used to re-implement the app's rule by
    /// hand (and before that a hardcoded `.prefix(3)`), which is how a review
    /// render drifts from what the shipped app shows.
    static func stopPhotoSelections(
        detail: TripRepository.TripDetail, full: TrackingConfig
    ) -> StopPhotoSelections {
        var rawPhotoCounts: [String: Int] = [:]
        var favoriteCounts: [String: Int] = [:]
        for stop in detail.stops {
            let atStop = detail.photos.filter { $0.stopId == stop.id }
            rawPhotoCounts[stop.id] = atStop.count
            favoriteCounts[stop.id] = atStop.filter { $0.isHighlight != 0 }.count
        }
        let candidates = RecapComposer.photoCandidates(detail: detail)
        return StopPhotoSelections(
            photosByStop: candidates.byStop, highlighted: candidates.highlighted,
            rawPhotoCounts: rawPhotoCounts, favoriteCounts: favoriteCounts
        )
    }

    /// The shipped path's first step (`RecapExportJob.compose`): the film ends
    /// at the destination, so the flight home comes off before anything else.
    static func filmRecords(
        detail: TripRepository.TripDetail, full: TrackingConfig
    ) -> (segments: [(segment: SegmentRecord, points: [TrackpointRecord])], stops: [StopRecord]) {
        let film = RecapComposer.filmRecords(
            segments: detail.segments, stops: detail.stops,
            epsilonM: full.simplify.epsilonM, matchedEpsilonM: full.matching.displayEpsilonM,
            homeRadiusM: full.discovery.awayRadiusM
        )
        print("KAMOME_DEMO_FILM_IMPORT homecoming: \(detail.segments.count - film.segments.count) legs, "
            + "\(detail.stops.count - film.stops.count) stops left out")
        return film
    }
}
