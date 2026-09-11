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
            return .failed(message: String(localized: "recap_failed"))
        }
        guard let plan = plan(composed) else {
            return .failed(message: String(localized: "recap_failed"))
        }
        let resolver = PhotoLibraryPhotoResolver()
        await warmDeckPhotos(trip: composed.trip, style: plan.style, resolver: resolver, channel: channel)
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
        guard let detail = try? repository.detail(tripId: request.tripId) else { return nil }
        let stats = TripStats.from(jsonString: detail.trip.statsJson)
        // Deck photo refs are selected here (data); the resolver loads the
        // bitmaps. Refs stay out of the render size.
        let photoRefs = request.photosEnabled ? selectStopPhotoRefs(detail: detail) : [:]
        let deck = RecapDeck(
            photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS,
            labelLeadS: config.export.deckLabelLeadS, photoMinHoldS: config.export.deckPhotoMinHoldS
        )
        // Typed legs (Fable review 2026-07-26): each stretch reaches the film
        // with its own transport mode and provenance, so a leg Kamome could not
        // reconstruct renders visibly as a guess rather than as road (PD-1).
        let legs = RecapComposer.legs(
            from: detail.segments,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        guard let trip = RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: detail.stops, stats: stats,
            photosByStop: photoRefs, deck: deck, stopHoldS: config.export.stopHoldS,
            rawPhotoCounts: rawPhotoCounts(detail: detail),
            favoriteCounts: favoriteCounts(detail: detail),
            weighting: config.export,
            everyLegRoutabilityEstablished:
                RecapComposer.everyLegRoutabilityEstablished(detail.segments)
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
            KamomeLog.recap.notice("""
                recap: film type UNKNOWN — routing has not answered for every leg, so a crossing \
                may not have been found; rendering the local film and a later export may differ
                """)
        case .multiRegion:
            KamomeLog.recap.notice("""
                recap: film type multi-region, \(journeyCount, privacy: .public) local journeys — \
                that film is not built, rendering the local one
                """)
        case .local:
            KamomeLog.recap.notice("recap: film type local — one journey, no crossing")
        case .oneDestination:
            KamomeLog.recap.notice("recap: film type one destination abroad — 2 local journeys")
        }
    }
}
