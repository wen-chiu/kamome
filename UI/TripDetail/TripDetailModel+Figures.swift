import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import KamomeTripComposer

/// What the stat card and the export button read off the trip. Moved here as
/// written (2026-10-08) when #242 took the model's body past SwiftLint's 250.
extension TripDetailModel {
    var stats: TripStats? {
        TripStats.from(jsonString: detail?.trip.statsJson)
    }

    /// **The film button can be pressed** — S5's entry. Only completed trips
    /// have a film to render. Naming is throttled and asynchronous; a film
    /// exported before its stops are named says "Unnamed stop" for each of them
    /// (Chiu 2026-08-04). It waits only for the stops a film shows (#160); the
    /// banner keeps counting the rest. A trip of one place has no film to make
    /// and is refused here, before the export could fail (Chiu 2026-11-04,
    /// #350). The button and Home's path to the sheet both wait on this.
    @MainActor var canMakeFilm: Bool {
        detail?.trip.endedAt != nil && !isNamingFilmStops && !filmHasOnePlace
    }

    /// **The one sentence under a button that will not come back**: a finished
    /// trip of one place. Never for a trip still recording, nor while naming,
    /// which only waits and has its own banner.
    var saysFilmHasOnePlace: Bool {
        detail?.trip.endedAt != nil && filmHasOnePlace
    }

    /// Every stop either film length presents. Both, because the length is
    /// chosen on the export sheet, after the button this gates.
    nonisolated static func filmStopIds(_ detail: TripRepository.TripDetail, config: TrackingConfig) -> Set<String> {
        FilmLength.allCases.reduce(into: Set<String>()) { ids, length in
            ids.formUnion(RecapComposer.filmPlan(detail: detail, config: config, length: length).decks.keys)
        }
    }
}
