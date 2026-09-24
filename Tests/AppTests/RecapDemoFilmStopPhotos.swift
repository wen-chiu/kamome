@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence

/// Split out of `RecapDemoFilmTests.importedRecap` (lint length only, Chiu
/// 2026-08-07).
extension RecapDemoFilmTests {
    /// **The app's own selection input** (`RecapComposer.photoInputs`): every
    /// stop's photographs in time order, the starred ones and the counts the
    /// stops are ranked on; the composer picks each deck after allocation. This
    /// used to re-implement the app's rule by hand (and before that a hardcoded
    /// `.prefix(3)`), which is how a review render drifts from what ships.
    static func stopPhotoSelections(detail: TripRepository.TripDetail) -> RecapComposer.PhotoInputs {
        RecapComposer.photoInputs(detail: detail)
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
