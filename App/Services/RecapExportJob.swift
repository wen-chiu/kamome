import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer

/// One trip becoming one film: routing, composition, the timeline, the render,
/// and the record that outlives it.
///
/// **This used to be `RecapModel.runExport`**, and it moved here whole in the
/// Phase 4 closeout step 2 (Chiu 2026-09-10) for one reason: it was owned by a
/// view's `@State` and died when the sheet closed. Nothing about the pipeline
/// changed in the move — `Core/ExportEngine` is untouched, and the golden-frame
/// and continuity gates cover that.
///
/// It is a value with no published state. Everything a screen shows travels out
/// through `RecapExportChannel`, and `RecapExportCoordinator` is the only thing
/// that runs one.
@MainActor
struct RecapExportJob: RecapExportRunning {
    let request: RecapExportRequest
    let config: TrackingConfig
    let repository: TripRepository

    func run(_ channel: RecapExportChannel) async -> RecapExportOutcome {
        await matchRoutes(channel)
        guard let composed = compose() else {
            KamomeLog.recap.error("export failed — the trip could not be composed into a film")
            return .failed(message: String(localized: "recap_failed"))
        }
        guard let plan = plan(composed) else {
            KamomeLog.recap.error("export failed — no film plan (base map or timeline)")
            return .failed(message: String(localized: "recap_failed"))
        }
        let resolver = PhotoLibraryPhotoResolver()
        await warmDeckPhotos(trip: composed.trip, style: plan.style, resolver: resolver, channel: channel)
        // Cancel during the download phase ends here, before a frame is drawn.
        guard channel.shouldContinue() else { return .cancelled }
        return await render(composed: composed, plan: plan, resolver: resolver, channel: channel)
    }

    // MARK: - Routing

    /// Best-effort §4.4 matching before composing, bounded by
    /// `matching.trip_budget_s` for the whole trip. The replay should follow
    /// roads whenever a server is around.
    ///
    /// Through the coordinator, so a film started seconds after an import
    /// **joins** that import's run instead of starting a second one over the
    /// same legs (2026-08-15). Concurrent runs were verified not to corrupt
    /// anything — `DatabaseQueue` serialises, and the write is one column that
    /// does not read itself — but two runs mean two budgets and two verdicts for
    /// one trip, and the screen can only show one.
    private func matchRoutes(_ channel: RecapExportChannel) async {
        let report = await RouteMatchCoordinator.shared.result(
            tripId: request.tripId,
            service: RouteMatchService(repository: repository, matching: config.matching)
        )
        channel.routing(report)
    }

    // MARK: - Composition

    /// The trip, as the film's data model sees it, plus the detail row the
    /// render still needs (the subject id).
    struct Composed {
        let trip: RecapTrip
        let detail: TripRepository.TripDetail
    }

    private func compose() -> Composed? {
        guard let detail = Stored.read("detail", { try repository.detail(tripId: request.tripId) }) else { return nil }
        let stats = TripStats.from(jsonString: detail.trip.statsJson)
        // Deck photo refs are selected here (data); the resolver loads the
        // bitmaps. Refs stay out of the render size.
        // The counts are read either way: which stops the film presents must not
        // change because photo cards are switched off, only whether they show.
        let photos = RecapComposer.photoInputs(detail: detail, analysis: config.photoAnalysis)
        // Which pick the film used — never waited for (ADR 2026-09-25 (d)).
        KamomeLog.recap.notice(
            "recap: photo pick — \(photos.analysis == nil ? "by time (analysis not complete)" : "analysed")"
        )
        let deck = RecapDeck(
            photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS,
            labelLeadS: config.export.deckLabelLeadS, photoMinHoldS: config.export.deckPhotoMinHoldS
        )
        // Typed legs (Fable review 2026-07-26): each stretch reaches the film
        // with its own transport mode and provenance, so a leg Kamome could not
        // reconstruct renders visibly as a guess rather than as road (PD-1).
        //
        // The film ends at the destination (ADR 2026-09-01): the flight home and
        // everything after it come off here, before anything is classified.
        let film = RecapComposer.filmRecords(
            segments: detail.segments, stops: detail.stops,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM,
            homeRadiusM: config.discovery.awayRadiusM
        )
        if film.segments.count < detail.segments.count {
            // Counts only — never where home is (`CLAUDE.md` §0).
            KamomeLog.recap.notice("""
                recap: the trip comes home — the film ends at the destination; \
                \(detail.segments.count - film.segments.count, privacy: .public) legs and \
                \(detail.stops.count - film.stops.count, privacy: .public) stops after the flight home are left out
                """)
        }
        let legs = RecapComposer.legs(
            from: film.segments,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        guard let trip = RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: film.stops, stats: stats,
            photosByStop: request.photosEnabled ? photos.byStop : [:], deck: deck, stopHoldS: config.export.stopHoldS,
            rawPhotoCounts: photos.rawCounts,
            favoriteCounts: photos.starredCounts,
            highlightedAssets: photos.highlighted,
            pickedAssets: photos.picked, pickedCounts: photos.pickedCounts,
            analysis: photos.analysis,
            highlightMaxPhotos: config.photoImport.deckHighlightMaxPhotos,
            weighting: config.export,
            everyLegRoutabilityEstablished:
                RecapComposer.everyLegRoutabilityEstablished(film.segments),
            clock: TripClock(stops: detail.stops)
        ) else { return nil }
        announceFilmType(trip)
        return Composed(trip: trip, detail: detail)
    }

    /// The film type is derived, never stored (`RecapFilmType`), so it is
    /// resolved here — after routing has had whatever time it has had — and
    /// announced. `.unknown` renders the local film, and saying so is the
    /// difference between a declared fallback and a silent one: a trip whose
    /// crossing has not been routed yet looks exactly like a trip with no
    /// crossing, and only this line tells them apart (`Arch.md` §6).
    private func announceFilmType(_ trip: RecapTrip) {
        let journeyCount = RecapFilmType.distinctJourneyCount(legs: trip.legs)
        switch trip.filmType {
        case .unknown:
            // Which of the two ways to land here this is: no leg was ever read as
            // a crossing (0 below), or some were and the bounding-box fold still
            // called it one region. Counts only — never a coordinate (`CLAUDE.md`
            // §0).
            let crossingLegs = trip.legs.filter(\.isCrossing).count
            KamomeLog.recap.notice("""
                recap: film type UNKNOWN — routing has not answered for every leg, so a crossing \
                may not have been found; rendering the local film and a later export may differ \
                (\(journeyCount, privacy: .public) local journeys counted, \
                \(crossingLegs, privacy: .public)/\(trip.legs.count, privacy: .public) legs marked crossing)
                """)
        case .multiRegion:
            // `renderedForm` maps this to the type-2 form — the film flies the
            // first crossing and plays the rest in the body. This line used to
            // say "rendering the local one", which was never what happened.
            KamomeLog.recap.notice("""
                recap: film type multi-region, \(journeyCount, privacy: .public) local journeys — \
                that film is not built; rendering the one-destination form (flies the first crossing)
                """)
        case .local:
            KamomeLog.recap.notice("recap: film type local — one journey, no crossing")
        case .oneDestination:
            KamomeLog.recap.notice("recap: film type one destination abroad — 2 local journeys")
        }
    }
}
