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
/// of four completely different things had happened. That was tolerable against
/// a routing box on the developer's LAN, which either answered or did not. A
/// hosted provider adds timeouts, 429s, cold starts and outages, and the honest
/// response to those is "try again", while the honest response to a ferry
/// crossing is "there is no road here". The same dashed line cannot mean both.
struct RouteMatchReport: Equatable {
    /// Legs the run was willing to attempt.
    var attempted = 0
    /// Legs that came back with road geometry, now stored.
    var reconstructed = 0
    /// The provider answered and the answer was "no road route joins these" —
    /// a ferry, an island hop, a detour the photos never evidenced. Permanent.
    var noPlausibleRoute = 0
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
        if noPlausibleRoute > 0 { return .someLegsHaveNoRoad }
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
    private let matcher: RouteMatchProviding
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
        matcher = provider ?? OSRMMatchProvider(config: matching)
        self.reconstructor = reconstructor ?? OSRMRouteProvider(config: matching)
        // **An injected provider need not be talking to the configured host**
        // (twice-confirmed, 2026-08-15). The desk harnesses inject a provider
        // built on `withBaseURL(…)`, and this line then named the config's URL —
        // which is empty in the repository. It is the first line anyone reads
        // when diagnosing routing, including the P0, so it must never name a
        // server the run did not use.
        let configured = matching.baseURL
        if provider == nil, reconstructor == nil {
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
            \(report.noPlausibleRoute) have no road route, \(report.unreachable) unreachable, \
            \(report.rateLimited) rate-limited, \(report.skipped) never asked — the rest draw dashed (PD-1)
            """)
        return report
    }

    /// One leg, with its four possible answers kept apart. A nil outcome is the
    /// provider's own verdict — it answered, and the answer was "no road route".
    /// A thrown `RouteProviderFailure` means nobody answered.
    private func route(
        _ trace: [RouteMatchPoint],
        source: SegmentSource,
        segmentId: String,
        into report: inout RouteMatchReport
    ) async {
        do {
            let outcome: RouteMatchOutcome?
            switch source {
            case .exif, .timeline: outcome = try await reconstructor.route(trace)
            case .gpsHifi, .gpsPassive: outcome = try await matcher.match(trace)
            }
            guard let outcome else {
                report.noPlausibleRoute += 1
                return
            }
            try? repository.setMatchedPolyline(
                segmentId: segmentId, encodedPolyline: outcome.encodedPolyline
            )
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

    private func shouldReconstruct(_ segment: SegmentRecord, points: [TrackpointRecord]) -> Bool {
        guard segment.matchedPolyline == nil, points.count >= 2 else { return false }
        // The self-hosted server runs the car profile: drive and scooter follow
        // the drivable network. Walks stay raw — feet ignore roads, and snapping
        // a stroll to the nearest street invents a journey (PD-8). Cycle,
        // transit and unknown stay raw for the same reason.
        switch TransportMode(rawValue: segment.mode) {
        case .drive, .scooter: return true
        default: return false
        }
    }
}
