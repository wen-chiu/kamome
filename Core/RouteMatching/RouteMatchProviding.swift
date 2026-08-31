import Foundation

/// One trackpoint as matching input. Plain values so callers can feed
/// persistence records, replay fixtures, or imported points (§4.7) alike.
public struct RouteMatchPoint: Equatable, Sendable {
    public let ts: Double
    public let lat: Double
    public let lon: Double
    /// Horizontal accuracy in meters, if known — becomes the per-point
    /// search radius (floored by `matching.radius_m`).
    public let hAccM: Double?

    public init(ts: Double, lat: Double, lon: Double, hAccM: Double? = nil) {
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.hAccM = hAccM
    }
}

/// A confident snap of one segment's trace onto the road network.
public struct RouteMatchOutcome: Equatable, Sendable {
    /// Road-following geometry, in trace order.
    public let geometry: [GeoPoint]
    /// Worst per-matching confidence that survived (0…1).
    public let confidence: Double

    public init(geometry: [GeoPoint], confidence: Double) {
        self.geometry = geometry
        self.confidence = confidence
    }

    /// The `segment.matched_polyline` storage form.
    public var encodedPolyline: String {
        EncodedPolyline.encode(geometry)
    }
}

/// Why a provider could not answer — thrown, never returned, because none of
/// these is a verdict about the geography (2026-08-15).
///
/// **The distinction that matters, and why it is being drawn now.** A leg with
/// no road geometry draws dashed, and until now every reason produced that same
/// dashed leg with nothing to tell them apart: a ferry crossing that genuinely
/// has no road route looked exactly like a server on the wrong Wi-Fi. That was
/// survivable against a routing box on the developer's LAN, which either
/// answered or did not. A hosted provider adds cold starts, quotas and outages —
/// failures that are *temporary*, and where the honest thing to tell the user is
/// "try again", not "there is no road here".
///
/// So: a `RouteReconstruction` means the provider **answered**, and the answer
/// says which of its verdicts applied — permanent, correct, dashed forever in the
/// `.noRoadHere` case. One of these means nobody answered — retryable, and never
/// the geography's fault.
public enum RouteProviderFailure: Error, Equatable, Sendable {
    /// Nothing answered: DNS, ATS, a LAN address on someone else's network, a
    /// dropped connection, a timeout, a cold start that outran `timeout_s`.
    case unreachable(String)
    /// Refused for load — HTTP 429, or a quota response. `retryAfterS` is the
    /// server's own advice when it gave any.
    case rateLimited(retryAfterS: Double?)
    /// Answered, with a status that is neither success nor an OSRM verdict.
    case refused(status: Int)
}

/// **What one reconstruction request established** — the named verdict that
/// replaced `RouteMatchOutcome?` on 2026-08-30.
///
/// **Why the optional had to go.** `GeoapifyRouteProvider` had six `return nil`
/// sites — routing switched off, too few waypoints after thinning, an answer it
/// could not read, the PD-3 detour gate, and the provider's own "there is no
/// road here" — and downstream they were one indistinguishable nil. Each was
/// named in the log as it happened and then forgotten by the type, so the only
/// record of *which* had occurred was a line in a device console.
///
/// That was survivable while every one of them merely produced a dashed leg.
/// It stopped being survivable when the **crossing beat** (`Docs/camera-arcs.md`
/// §0) made one of them load-bearing: a leg with no road is a journey by another
/// mode and earns its own stretch of film, while a leg nobody asked about is a
/// leg nobody asked about. Guessing which nil meant water is the one failure the
/// whole cross-region design exists to avoid, so the verdict travels as a value.
///
/// The `RouteProviderFailure` distinction is unchanged and orthogonal: these are
/// the answers, that is thrown when **nobody answered**.
public enum RouteReconstruction: Equatable, Sendable {
    /// A road route came back and survived the detour gate. Store it; the leg
    /// draws solid as `.reconstructed`.
    case routed(RouteMatchOutcome)
    /// **The provider answered, and there is no road joining these places.**
    /// Geoapify's `400 No suitable edges near location` / `No path could be
    /// found` — a ferry, an island hop, a photograph taken on a beach.
    /// Permanent, correct, and the **only** verdict a crossing may be built on.
    case noRoadHere
    /// A route came back and `RoutePlausibility` refused it. **A road exists**;
    /// this particular route is not trustworthy, usually because one EXIF fix is
    /// plainly wrong. Draws dashed, and is emphatically *not* a crossing —
    /// treating it as one would fly a plane over a road.
    case implausible
    /// Nothing was established about the geography at all. Retryable in
    /// principle, and never a claim about the ground.
    case notEstablished(Reason)

    /// Why nothing was established. An enum rather than a message because these
    /// are three different states a caller may want to act on differently, and a
    /// string is a state nobody can switch over (`Arch.md` §5).
    public enum Reason: String, Equatable, Sendable, CaseIterable {
        /// `matching.base_url` is empty. The shipped default, and not a failure.
        case routingDisabled
        /// Fewer than two waypoints survived thinning, or no URL could be built.
        case tooFewWaypoints
        /// The provider answered 200 with something this client could not turn
        /// into a route: no feature, under two points, an unexpected geometry.
        case unreadableAnswer
    }

    /// The geometry, when there is any. Callers that only want to store a
    /// polyline should not have to switch over four cases to find out there
    /// isn't one.
    public var outcome: RouteMatchOutcome? {
        guard case let .routed(outcome) = self else { return nil }
        return outcome
    }
}

/// Boundary for map matching (§4.4) — the same one-file-per-backend
/// discipline as `MapRenderer` (§0 boundary rule): a backend's wire format
/// stays inside its own file, and future backends (e.g. a foot profile for walk
/// segments) conform here without touching callers.
///
/// Returns nil when no confident match exists (server disabled, trace too
/// short, confidence below the floor) — the caller keeps raw geometry.
/// Throws only for transport-level failures; callers treat both the same
/// way (fall back, never block — §4.4) but may log errors.
public protocol RouteMatchProviding: Sendable {
    func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome?
}

/// Boundary for route *reconstruction* — the sibling of `RouteMatchProviding`
/// for traces too sparse to map-match (typed-leg pass 2026-07-26).
///
/// **Why a second boundary rather than a second implementation of the first.**
/// The two answer different questions. Map matching asks "which road were these
/// dense GPS fixes on?" and needs the trace to be a near-continuous sample of
/// the drive. A photo-EXIF leg is nothing like that: three or four positions
/// hours apart, which a Hidden-Markov matcher will either reject outright or
/// match to an arbitrary road. The question there is "what is the plausible
/// driving route *through* these places?" — a routing query with the photos as
/// via-waypoints (PD-3). The caller does the same two things with both answers —
/// store the geometry, or keep the raw leg and render it inferred (PD-2) — but
/// only this side can say *why* there is no geometry, which is what
/// `RouteReconstruction` carries and `RouteMatchOutcome?` could not.
///
/// Answers with a **named verdict** (`RouteReconstruction`), never a guess and
/// never a bare optional: "there is no road here" and "we did not ask" are
/// different facts and the crossing beat is built on exactly one of them.
/// Throws only when nobody answered.
public protocol RouteReconstructing: Sendable {
    func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction
}
