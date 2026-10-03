import Foundation

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
    /// Legs the run was willing to attempt — including legs answered by a
    /// verdict already stored, which are not re-sent (2026-09-12), so
    /// `attempted - reconstructed` is still the number that draws dashed.
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
    /// A road route came back and the PD-3 detour gate refused it — or, since
    /// ADR 2026-10-03, it ran longer than a day's driving with no photograph
    /// along it (`RouteFeasibility`). A road exists; this one is not
    /// trustworthy. Dashed, and never flown.
    var implausibleRoute = 0
    /// Legs with a waypoint no road reaches — a beach, a cape (ADR 2026-09-23
    /// (c)). Dashed like a crossing, but not one.
    var offRoadNetwork = 0
    /// Legs judged on the phone as **too fast to have been driven** — a flight
    /// or a sea crossing (ADR 2026-09-24 (f), `LegPace`). Never sent to routing,
    /// so they are not in `attempted`; a crossing, and the film working.
    var beyondDriving = 0
    /// Legs routing **did** answer with a road, refused because no drive covers
    /// that road in the time the photographs allow (ADR 2026-10-03,
    /// `RouteFeasibility`) — a flight across connected land. Stored as
    /// `beyond_driving`, so a crossing; in `attempted`, unlike `beyondDriving`.
    /// A road refused for want of witnesses is counted in `implausibleRoute`.
    var routedButNotDriven = 0
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
        if noPlausibleRoute > 0 || implausibleRoute > 0 || offRoadNetwork > 0 { return .someLegsHaveNoRoad }
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
