import Foundation
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine

/// What one trip's routing run did — the whole of what callers and the UI need
/// to know (2026-08-15).
///
/// **Why a report rather than a Bool.** Every one of these outcomes used to
/// produce the same artifact: a film with dashed legs and no way to tell which
/// of several completely different things had happened. That was tolerable against
/// a routing box on the developer's LAN, which either answered or did not. A
/// hosted provider adds timeouts, 429s, cold starts and outages, and the honest
/// response to those is "try again", while the honest response to a ferry
/// crossing is "there is no road here". The same dashed line cannot mean both.
struct RouteMatchReport: Equatable {
    /// Legs the run was willing to attempt.
    var attempted = 0
    /// Legs that came back with road geometry, now stored.
    var reconstructed = 0
    /// The provider answered and the answer was **"there is no road here"** —
    /// a ferry, an island hop, a leg across water. Permanent, and the only
    /// verdict a cross-region crossing beat may be built on
    /// (`Docs/camera-arcs.md` §0).
    ///
    /// **Narrowed 2026-08-30.** It used to count every nil the reconstructor
    /// returned, which lumped in the detour gate, an unreadable answer and a
    /// disabled endpoint. Those are the two fields below.
    var noPlausibleRoute = 0
    /// A road route came back and the PD-3 detour gate refused it. A road
    /// exists; this one is not trustworthy. Dashed, and never flown.
    var implausibleRoute = 0
    /// Nothing was established about the ground at all — routing disabled, too
    /// few waypoints, or an answer the client could not read. Not a claim about
    /// the geography and not a provider failure either.
    var notEstablished = 0
    /// Nobody answered. Retryable, and never a fact about the geography.
    var unreachable = 0
    /// Refused for load. Retryable, and worth waiting before retrying.
    var rateLimited = 0
    /// Legs never attempted because `matching.trip_budget_s` ran out, or the
    /// caller cancelled. Retryable; nothing was learnt about them at all.
    var skipped = 0
    /// Routing is switched off (`base_url` empty). Not a failure.
    var isDisabled = false

    /// The headline: what a user would say went wrong, if anything.
    ///
    /// Ordered by what is most worth acting on rather than by count — one
    /// unreachable leg means the endpoint is in doubt for all of them, whereas
    /// a leg with genuinely no road route is the film working correctly.
    enum Headline: Equatable {
        case disabled
        case allRouted
        case someLegsHaveNoRoad
        case providerUnreachable
        case rateLimited
        case budgetExhausted
    }

    var headline: Headline {
        if isDisabled { return .disabled }
        if rateLimited > 0 { return .rateLimited }
        if unreachable > 0 { return .providerUnreachable }
        if skipped > 0 { return .budgetExhausted }
        // Both leave the film with a dashed leg the provider could not turn into
        // road, and the user-facing sentence for both is the same one it has
        // always been. Splitting the *counts* is what the crossing beat needed;
        // splitting the *message* is a copy decision nobody has made.
        if noPlausibleRoute > 0 || implausibleRoute > 0 { return .someLegsHaveNoRoad }
        return .allRouted
    }

    /// Whether anything here is worth telling the user about. A fully routed
    /// film, a disabled endpoint and a trip with nothing routable all say
    /// nothing — the film is simply what it is.
    var isWorthReporting: Bool {
        switch headline {
        case .disabled, .allRouted: return false
        case .someLegsHaveNoRoad, .providerUnreachable, .rateLimited, .budgetExhausted: return attempted > 0
        }
    }
}

/// Runs §4.4 road reconstruction over a stored trip: every road-mode segment
/// that has no `matched_polyline` yet is sent to the provider its data suits and
/// the result persisted. Best-effort by construction — failures leave raw
/// geometry in place and never block trip completion or recap (§4.4). What the
/// user *does* see is honesty: an unreconstructed leg renders inferred in the
/// film (PD-2), never as a confident road, and now the run says *why*.
///
/// **Two providers, dispatched on how the geometry was captured**
/// (typed-leg pass 2026-07-26). A recorded segment is a dense GPS trace and
/// belongs in `/match`, whose Hidden-Markov model expects exactly that. An
/// imported segment is three or four EXIF positions hours apart; `/match` either
/// rejects it or snaps it somewhere arbitrary, so it goes to `/route` with the
/// photo positions as via-waypoints (PD-3). Same storage, same fallback.
///
/// **Bounded and cancellable** (2026-08-15). `timeout_s` bounds one request and
/// nothing bounded the trip, so an import with many stops against an endpoint
/// that does not answer was one timeout after another — the app looked dead, for
/// minutes. Two limits fix that, and they are the same pair `RecapExporter`
/// already uses for the render: a caller-supplied `shouldContinue`, checked
/// before every leg, and a trip-level budget from config.
struct RouteMatchService {
    private let repository: TripRepository
    /// **Nil on the shipped path, deliberately** (2026-08-20 (d)). Map matching
    /// speaks OSRM's `/match`, and the endpoint is Geoapify now: a recorded
    /// trace sent there would put the full dense path in the query string of a
    /// request that can only 404 — a §0 exposure in exchange for nothing. So no
    /// matcher is constructed, `shouldReconstruct` stops offering recorded legs,
    /// and they keep the trace the phone actually saw, which
    /// `RecapComposer.provenance(for:)` already draws **solid** as `.recorded`.
    /// What is lost is snapping polish on a 50 m-sampled drive, and that is a
    /// Capture Beta concern. Injectable so Capture Beta — or a test — can supply
    /// one without this becoming a provider registry.
    private let matcher: RouteMatchProviding?
    private let reconstructor: RouteReconstructing
    private let config: TrackingConfig.Matching
    /// Logged, not used: the providers own the requests. What it answers is
    /// "which server did this build actually ask?" — the first question of the
    /// all-dashed failure, and one a finished film cannot answer.
    private let endpoint: String

    /// Takes the `matching` block rather than the whole config, because that is
    /// all it reads — and a test that needs a different budget should not have
    /// to rebuild every unrelated tunable to say so.
    init(
        repository: TripRepository,
        matching: TrackingConfig.Matching,
        provider: RouteMatchProviding? = nil,
        reconstructor: RouteReconstructing? = nil
    ) {
        self.repository = repository
        config = matching
        matcher = provider
        self.reconstructor = reconstructor ?? GeoapifyRouteProvider(config: matching)
        // **An injected provider need not be talking to the configured host**
        // (twice-confirmed, 2026-08-15). The desk harnesses inject a provider
        // built on `withBaseURL(…)`, and this line then named the config's URL —
        // which is empty in the repository. It is the first line anyone reads
        // when diagnosing routing, including the P0, so it must never name a
        // server the run did not use.
        let configured = matching.baseURL
        if reconstructor == nil {
            endpoint = configured.isEmpty ? "(none — matching disabled)" : configured
        } else {
            endpoint = "(injected provider — the configured \"\(configured)\" is not necessarily what it asks)"
        }
    }

    /// Idempotent: already-matched segments are skipped, so every caller (trip
    /// end, import, recap export) can fire it freely.
    ///
    /// **Idempotent is not the same as concurrency-safe, and this is safe for a
    /// different reason** (verified 2026-08-15). `AppDatabase` is a GRDB
    /// `DatabaseQueue`, which serialises every read and write; `setMatchedPolyline`
    /// is a one-row, one-column UPDATE whose value does not depend on the row's
    /// previous value; and this method never writes nil, so no run can un-match a
    /// leg another run matched. Two concurrent runs therefore cannot corrupt or
    /// interleave state — they can only do the same work twice, and agree.
    ///
    /// Doing it twice is still worth preventing, because a *per-run* budget is
    /// not a per-trip budget and two runs report two answers for one trip. That
    /// is `RouteMatchCoordinator`'s job, not a lock's.
    ///
    /// `shouldContinue` is checked before each leg; the budget is checked with
    /// it. Both leave the remaining legs raw and dashed, which is a state the
    /// film already knows how to draw.
    @discardableResult
    func matchTrip(
        tripId: String,
        shouldContinue: () -> Bool = { true },
        progress: ((Int, Int) -> Void)? = nil
    ) async -> RouteMatchReport {
        var report = RouteMatchReport()
        report.isDisabled = config.baseURL.isEmpty
        guard let detail = try? repository.detail(tripId: tripId) else { return report }
        let attempted = detail.segments.filter { shouldReconstruct($0.segment, points: $0.points) }
        report.attempted = attempted.count
        KamomeLog.routing.notice("""
            matchTrip \(tripId, privacy: .public): \(attempted.count)/\(detail.segments.count) legs routable \
            against "\(endpoint, privacy: .public)", budget \(config.tripBudgetS, format: .fixed(precision: 0))s
            """)

        let deadline = ContinuousClock.now + .seconds(config.tripBudgetS)
        for (index, item) in attempted.enumerated() {
            let wanted = shouldContinue()
            guard wanted, ContinuousClock.now < deadline else {
                // Named, not silent: "we stopped asking" is a different film
                // from "there is no road there", and only one is worth a retry.
                report.skipped = attempted.count - index
                KamomeLog.routing.error("""
                    matchTrip \(tripId, privacy: .public): STOPPED after \(index) legs — \
                    \(wanted ? "trip_budget_s exhausted" : "cancelled"); \
                    \(report.skipped) legs left raw and retryable
                    """)
                break
            }
            let trace = item.points.map {
                RouteMatchPoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAccM: $0.hAcc)
            }
            await route(trace, source: item.segment.segmentSource, segmentId: item.segment.id, into: &report)
            progress?(index + 1, attempted.count)
        }

        // The headline a dogfooder needs: how much of the film will draw as road.
        KamomeLog.routing.notice("""
            matchTrip \(tripId, privacy: .public): \(report.reconstructed)/\(report.attempted) legs reconstructed; \
            \(report.noPlausibleRoute) have NO ROAD (crossings), \(report.implausibleRoute) implausible, \
            \(report.notEstablished) not established, \(report.unreachable) unreachable, \
            \(report.rateLimited) rate-limited, \(report.skipped) never asked — the rest draw dashed (PD-1)
            """)
        return report
    }

    /// One leg, with every answer kept apart — and, for a reconstructed leg,
    /// **written down**. A `RouteReconstruction` is the provider's own verdict;
    /// a thrown `RouteProviderFailure` means nobody answered.
    ///
    /// The write is what makes the crossing beat possible at all. Routing is a
    /// detached background step since 2026-08-15 and the recap may be rendered
    /// days later, so a verdict that lived only in this report would be gone by
    /// the time the film needed it (`SegmentRoutability`).
    private func route(
        _ trace: [RouteMatchPoint],
        source: SegmentSource,
        segmentId: String,
        into report: inout RouteMatchReport
    ) async {
        do {
            let outcome: RouteMatchOutcome?
            switch source {
            case .exif, .timeline:
                outcome = reconstructed(
                    try await reconstructor.route(trace), segmentId: segmentId, into: &report
                )
                guard outcome != nil else { return }
            case .gpsHifi, .gpsPassive:
                guard let matcher else {
                    // Unreachable — `shouldReconstruct` filters recorded legs out
                    // when there is no matcher. Named rather than counted as "no
                    // road here", which would be a claim about the geography.
                    KamomeLog.routing.error(
                        "matchTrip: a recorded leg reached routing with no matcher configured — left raw"
                    )
                    report.skipped += 1
                    return
                }
                // Map matching keeps its optional: `RouteMatchProviding` answers
                // "which road were these dense fixes on?", and a nil there is a
                // confidence floor, never a claim that no road exists. No matcher
                // is constructed on the shipped path (see `matcher`).
                guard let matched = try await matcher.match(trace) else {
                    report.notEstablished += 1
                    return
                }
                outcome = matched
            }
            guard let outcome else {
                report.notEstablished += 1
                return
            }
            try? repository.setMatchedPolyline(
                segmentId: segmentId, encodedPolyline: outcome.encodedPolyline
            )
            try? repository.setRoutability(segmentId: segmentId, .road)
            report.reconstructed += 1
        } catch let failure as RouteProviderFailure {
            switch failure {
            case .unreachable, .refused: report.unreachable += 1
            case .rateLimited: report.rateLimited += 1
            }
        } catch {
            // A provider that throws something else is still "nobody answered";
            // it is not evidence about the geography.
            report.unreachable += 1
        }
    }

    /// Records one reconstruction verdict and returns its geometry, if any.
    ///
    /// **Two of the four are written down and two are not**, and that asymmetry
    /// is the whole point: `.noRoadHere` and `.implausible` are facts about the
    /// ground that a later render must be able to read, while
    /// `.notEstablished(…)` is the absence of a fact and NULL is how the schema
    /// says so (`SegmentRoutability`).
    private func reconstructed(
        _ reconstruction: RouteReconstruction, segmentId: String, into report: inout RouteMatchReport
    ) -> RouteMatchOutcome? {
        switch reconstruction {
        case let .routed(outcome):
            return outcome
        case .noRoadHere:
            // The one verdict that is a fact about the ground, and the only one a
            // crossing beat may be built on.
            try? repository.setRoutability(segmentId: segmentId, .noRoad)
            report.noPlausibleRoute += 1
        case .implausible:
            // A road exists and this route is not it. Stored so a later reader
            // cannot mistake the dashed line for water.
            try? repository.setRoutability(segmentId: segmentId, .implausibleRoute)
            report.implausibleRoute += 1
        case let .notEstablished(reason):
            KamomeLog.routing.notice(
                "matchTrip: nothing established for one leg — \(reason.rawValue, privacy: .public)"
            )
            report.notEstablished += 1
        }
        return nil
    }

    private func shouldReconstruct(_ segment: SegmentRecord, points: [TrackpointRecord]) -> Bool {
        guard segment.matchedPolyline == nil, points.count >= 2 else { return false }
        // Requests go out on the drive profile: drive and scooter follow the
        // drivable network. Walks stay raw here — snapping a stroll to the
        // nearest street invents a journey (PD-8). Cycle, transit and unknown
        // stay raw for the same reason. Spec v1.8 §4.4.1 gives walks their own
        // profile later; that is a new request shape, not a loosening of this.
        switch TransportMode(rawValue: segment.mode) {
        case .drive, .scooter: break
        default: return false
        }
        // A recorded trace needs a map matcher, and there is none on this
        // endpoint (see `matcher`). Offering the leg anyway would report it as a
        // routing failure; it is not one — the leg already draws solid on the
        // trace the phone recorded.
        switch segment.segmentSource {
        case .exif, .timeline: return true
        case .gpsHifi, .gpsPassive: return matcher != nil
        }
    }
}
