import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **Was this leg too fast to have been driven?** (ADR 2026-09-24 (e)).
///
/// The offline half of the crossing verdict. Routing can only say "no road"
/// when the provider's search concludes, and a leg from Taiwan to Vietnam may
/// never conclude inside `timeout_s` once OSM's cross-strait ferries join the
/// island to a continent (`Docs/handoff-vietnam-crossing.md`). Physics answers
/// first and asks nobody: a pace no drive can average is a flight or a sea
/// crossing, and the leg's coordinates never leave the phone (§0).
///
/// **One-sided.** `true` proves the leg was not driven; `false` proves nothing —
/// an overnight gap hides a flight — and the leg goes to routing as before.
///
/// **Clocks are not trusted across time zones.** A photo's instant is only as
/// good as the zone its capture time was read in. An iPhone stores the offset
/// and the instant is exact, but a camera without one, or a clock the traveller
/// reset on landing, shifts one end of the leg by up to the zone difference
/// between the two places. A constant error on both ends cancels; the error that
/// survives is bounded by that difference. So the elapsed time is **padded by
/// the widest zone gap the two longitudes allow** before the pace is taken, and
/// the padding only ever makes a leg look slower — a clock error can hide a
/// flight, never invent one.
public enum LegPace {
    /// Whether the straight line from `start` to `end` was covered faster than
    /// `crossing_pace_min_kmh` even after the clock allowance, over at least
    /// `crossing_pace_min_distance_m`.
    public static func isBeyondDriving(
        from start: RouteMatchPoint,
        to end: RouteMatchPoint,
        config: TrackingConfig.Matching
    ) -> Bool {
        let distanceM = Geo.distanceM(latA: start.lat, lonA: start.lon, latB: end.lat, lonB: end.lon)
        guard distanceM >= config.crossingPaceMinDistanceM, config.crossingPaceMinKmh > 0 else { return false }
        // Photos are ordered by time, so a negative gap is a clock error, and
        // zero is the least time the leg could have taken.
        let elapsedS = max(0, end.ts - start.ts) + clockAllowanceS(from: start, to: end, config: config)
        guard elapsedS > 0 else { return true }
        let paceKmh = (distanceM / 1000) / (elapsedS / 3600)
        return paceKmh >= config.crossingPaceMinKmh
    }

    /// How far the two ends' clocks may disagree because of time zones alone.
    ///
    /// Solar time moves an hour per 15° of longitude; civil zones follow it
    /// loosely, which `crossing_pace_clock_margin_s` covers. A leg over the
    /// antimeridian can also move the calendar a whole day, so it gets one.
    static func clockAllowanceS(
        from start: RouteMatchPoint,
        to end: RouteMatchPoint,
        config: TrackingConfig.Matching
    ) -> Double {
        let rawDegrees = abs(end.lon - start.lon)
        let crossesAntimeridian = rawDegrees > 180
        let spanDegrees = crossesAntimeridian ? 360 - rawDegrees : rawDegrees
        let zoneS = spanDegrees / 15 * 3600
        return zoneS + config.crossingPaceClockMarginS + (crossesAntimeridian ? 86_400 : 0)
    }
}
