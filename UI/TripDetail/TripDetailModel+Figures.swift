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

    /// Every stop either film length presents. Both, because the length is
    /// chosen on the export sheet, after the button this gates.
    nonisolated static func filmStopIds(_ detail: TripRepository.TripDetail, config: TrackingConfig) -> Set<String> {
        FilmLength.allCases.reduce(into: Set<String>()) { ids, length in
            ids.formUnion(RecapComposer.filmPlan(detail: detail, config: config, length: length).decks.keys)
        }
    }
}
