import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence

/// A film's ceiling, applied to the decks the film will actually show
/// (Chiu 2026-09-27) — split out of `RecapComposer+Photos` for its size budget.
extension RecapComposer {
    /// Which stops the film presents, what each is allocated, and the app's
    /// priority over them (`StopPhotoAllocator.priorityOrder`; 0 is kept
    /// longest). `priority` is empty for a film with no ranking — `.full`, or no
    /// weighting at all — which is never fitted. `deckCeiling` is where the
    /// ceiling took a highlight's lift back: that stop shows at most this many.
    struct Selection {
        var kept: [StopRecord]
        var allocation: [String: Int]
        var priority: [String: Int] = [:]
        var deckCeiling: [String: Int] = [:]
    }

    /// Holds the **app's own choice** for a highlight film to `ceilingS`
    /// (`durationCeilingS`: 90 s short, 300 s standard), at each deck's final
    /// size — after highlights have lifted it (`StopPhotoAllocator.fittedToCeiling`): extra
    /// photographs go first, then whole stops, lowest priority first.
    ///
    /// **Before the person's word, never after it** (Chiu 2026-09-25: editing
    /// one stop never moves another in or out). Fitting the finished plan
    /// instead would let a stop put in push one of the app's out — caught by
    /// `FilmPhotoChoicesTests` on the first run. So the app's part fits, and a
    /// stop the person adds or picks for goes on top; the sheet says when that
    /// carries the film past the ceiling.
    static func fitToCeiling(
        _ ranked: Selection, ceilingS: Double, inputs: PhotoInputs, highlightMaxPhotos: Int,
        weighting: TrackingConfig.Export
    ) -> Selection {
        let decks = ranked.kept.map { stop -> StopPhotoAllocator.PresentedDeck in
            let shown = deckPhotos(
                inputs.byStop[stop.id] ?? [], allocated: ranked.allocation[stop.id] ?? 0,
                highlightedAssets: inputs.highlighted, highlightMaxPhotos: highlightMaxPhotos,
                analysis: inputs.analysis
            ).count
            return StopPhotoAllocator.PresentedDeck(photos: shown, priority: ranked.priority[stop.id] ?? 0)
        }
        let fitted = StopPhotoAllocator.fittedToCeiling(decks, ceilingS: ceilingS, config: weighting)
        var result = Selection(kept: [], allocation: ranked.allocation, priority: ranked.priority)
        for (stop, (deck, count)) in zip(ranked.kept, zip(decks, fitted)) {
            guard let count else {
                result.allocation[stop.id] = nil
                continue
            }
            result.kept.append(stop)
            if count < deck.photos { result.deckCeiling[stop.id] = count }
        }
        return result
    }

    /// **How long the film will run, before it exists** (Chiu 2026-09-27,
    /// reopening ADR 2026-09-26 (c) item 7). `photoCounts` are the presented
    /// decks' sizes in trip order — zeros when photo cards are off, exactly
    /// as the export composes them.
    ///
    /// The same plan the timeline sizes itself with
    /// (`LinearTimeline.plannedDurationS`), so the two cannot drift. What it
    /// cannot see is what happens after routing: a type-2 film drops the
    /// origin's stops (`RecapTypeTwoFilm`), so the
    /// finished film can be **shorter** than this, never longer (INFERRED from
    /// the plan being monotone in its decks; `FilmLengthEstimateTests` pins the
    /// equality on a local trip).
    static func estimatedFilmS(photoCounts: [Int], config: TrackingConfig) -> Double {
        LinearTimeline.plannedDurationS(photoCounts: photoCounts, config: config.export)
    }
}
