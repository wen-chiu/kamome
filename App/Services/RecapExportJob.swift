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
        // **Where the wall-clock went, on every exit** (Chiu 2026-09-27): the
        // `render cost` line covers the drawing alone and only a finished film,
        // while routing and iCloud downloads can dominate a slow export. The
        // lines are then kept past this launch (`ExportLogHistory`), so a
        // tester can share them whenever they get round to it.
        let clock = ExportStageClock()
        KamomeLog.recap.notice("export: length \(request.length.rawValue, privacy: .public)")
        let outcome = await runStages(channel, clock: clock)
        clock.report(outcome: outcome)
        ExportLogHistory.keep(since: clock.startedAt, keptExports: config.export.pipeline.keptExportLogs)
        return outcome
    }

    private func runStages(_ channel: RecapExportChannel, clock: ExportStageClock) async -> RecapExportOutcome {
        channel.stage(.findingRoads)
        clock.enter("roads")
        // Cancel is read while the roads are found, not after (#277): routing
        // may take `trip_budget_s`, and nothing is drawn yet to stop between.
        guard await matchRoutes(channel), channel.shouldContinue() else { return .cancelled }
        channel.stage(.preparingPhotos)
        clock.enter("compose")
        guard let composed = compose() else {
            KamomeLog.recap.error("export failed — the trip could not be composed into a film")
            return Self.failed
        }
        guard let plan = plan(composed) else {
            KamomeLog.recap.error("export failed — no film plan (base map or timeline)")
            return Self.failed
        }
        clock.enter("photos")
        let resolver = PhotoLibraryPhotoResolver()
        await warmDeckPhotos(trip: composed.trip, style: plan.style, resolver: resolver, channel: channel)
        // Cancel during the download phase ends here, before a frame is drawn.
        guard channel.shouldContinue() else { return .cancelled }
        channel.stage(.drawing)
        clock.enter("drawing")
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
    ///
    /// **Cancel stops the export's wait, not the routing** (#277). The run may
    /// be an import's, and every verdict it reaches is stored either way; what
    /// the person cancelled is the film. Returns false when they did.
    private func matchRoutes(_ channel: RecapExportChannel) async -> Bool {
        let (tripId, service) = (
            request.tripId, RouteMatchService(repository: repository, matching: config.matching)
        )
        guard let report = await Self.waiting(
            for: { await RouteMatchCoordinator.shared.result(tripId: tripId, service: service) },
            unless: channel.shouldContinue
        ) else {
            KamomeLog.recap.notice("export cancelled while finding roads — routing carries on for the trip")
            return false
        }
        channel.routing(report)
        return true
    }

    /// `work`'s answer, or nil as soon as `shouldContinue` turns false — read
    /// every `cancelPollInterval` while `work` runs. `work` is not cancelled:
    /// it finishes on its own, and its answer is dropped.
    static func waiting<Value: Sendable>(
        for work: @escaping @MainActor () async -> Value,
        unless shouldContinue: @escaping @Sendable () -> Bool
    ) async -> Value? {
        let done = SharedFlag()
        let task = Task { @MainActor in
            let value = await work()
            done.set()
            return value
        }
        while !done.isSet {
            guard shouldContinue() else { return nil }
            try? await Task.sleep(for: cancelPollInterval)
        }
        return await task.value
    }

    /// How often a wait with nothing to draw reads Cancel — the same tenth of
    /// a second the render's progress reports at (`progressInterval`).
    static let cancelPollInterval: Duration = .milliseconds(100)

    // MARK: - Composition

    /// The trip, as the film's data model sees it, plus the detail row the
    /// render still needs (the subject id).
    struct Composed {
        let trip: RecapTrip
        let detail: TripRepository.TripDetail
    }

    private func compose() -> Composed? {
        guard let detail = Stored.read("detail", { try repository.detail(tripId: request.tripId) }) else { return nil }
        guard let composed = RecapComposer.filmComposition(
            detail: detail, config: config, photosEnabled: request.photosEnabled, length: request.length
        ) else { return nil }
        // Which pick the film used — never waited for (ADR 2026-09-25 (d)).
        KamomeLog.recap.notice(
            "recap: photo pick — \(composed.analysed ? "analysed" : "by time (analysis not complete)")"
        )
        if composed.droppedSegments > 0 {
            // Counts only — never where home is (`CLAUDE.md` §0).
            KamomeLog.recap.notice("""
                recap: the trip comes home — the film ends at the destination; \
                \(composed.droppedSegments, privacy: .public) legs and \
                \(composed.droppedStops, privacy: .public) stops after the flight home are left out
                """)
        }
        let trip = composed.trip
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
