import Foundation

/// **The route's one distance axis, and the two different questions asked of it**
/// — split out of `CameraPath` on 2026-09-03, when those two answers stopped
/// being the same number.
///
/// Everything here resolves "how far along is the subject at `time`" and what
/// falls out of it: the reveal's head, the polyline prefix under it, and the
/// point and heading at a distance. One axis, warped once by the film's clock, so
/// the trail, the sprite and the odometer can never disagree about where the
/// journey has got to.
///
/// The exception is the **odometer**, and it is the reason for the split. The
/// reveal must have the flown metres — the dashed leg has to be drawn while the
/// sprite is on it — and a viewer must not be told them: on `auckland-crossing`
/// the HUD read 8,755 km before the trip had started and 9,024 km at the end,
/// 97% of it a flight nobody drove (Chiu 2026-09-02). Both readers live here so
/// the contrast is one file rather than a comment pointing at another.
///
/// The flight's own distance is not deleted. It appears exactly once, on the
/// Journey Card, labelled as the flight.
extension CameraPath {
    /// The reveal's head: along-route metres, ⚠️ crossings included — the
    /// odometer is `CameraPathDistance` and deliberately is not this.
    public func traveledDistanceM(atTime time: Double) -> Double {
        state(atTime: time).distanceM
    }

    /// Where the trail reveal has reached at `time`: how many route vertices lie
    /// fully behind the subject, plus the interpolated head point it stops at.
    ///
    /// Exposed as an index rather than only as points (typed-leg pass
    /// 2026-07-26) so a caller holding the route's leg boundaries can split the
    /// reveal per leg. `CameraPath` stays the single owner of the speed-warp
    /// math; the timeline just asks it where the cut fell.
    public func revealCut(atTime time: Double) -> (vertexCount: Int, head: Point) {
        let distanceM = traveledDistanceM(atTime: time)
        var vertexCount = 0
        for vertexM in cumulativeM where vertexM < distanceM { vertexCount += 1 }
        return (vertexCount, coordinate(atDistance: distanceM))
    }

    /// Route vertices already passed at `time`, closed with the interpolated
    /// head point, ready for the traveled-polyline stroke (§4.5 step 2).
    public func routePrefix(atTime time: Double) -> [Point] {
        let cut = revealCut(atTime: time)
        return Array(route[0..<cut.vertexCount]) + [cut.head]
    }

    // Internal, not private: `position(atTime:)` and the prologue still read
    // these from `CameraPath.swift`, and Swift scopes `private` to the file.
    func state(atTime time: Double) -> (distanceM: Double, holdIndex: Int?) {
        let clamped = min(max(time, 0), durationS)
        // The timeline is a handful of entries per stop — linear scan is fine.
        let entry = timeline.last(where: { $0.startS <= clamped }) ?? timeline[0]
        switch entry.phase {
        case let .hold(stopIndex, atM):
            return (atM, stopIndex)
        // A crossing moves the subject exactly as travel does — eased from one
        // end to the other — and only the *camera* treats it differently. The
        // sprite still crosses the water, which is what makes the discontinuity
        // narrated rather than excused (`Docs/camera-arcs.md` §8).
        case let .travel(fromM, toM), let .crossing(fromM, toM):
            let span = entry.endS - entry.startS
            let progress = span > 0 ? (clamped - entry.startS) / span : 1
            let eased = Self.smoothstep(min(max(progress, 0), 1))
            return (fromM + (toM - fromM) * eased, nil)
        }
    }

    func coordinate(atDistance distanceM: Double) -> Point {
        Self.coordinate(atDistance: distanceM, route: route, cumulativeM: cumulativeM)
    }

    /// Heading (deg) of the route segment bracketing `distanceM` — the vehicle
    /// faces the way it is travelling. Binary search mirrors `coordinate`.
    func heading(atDistance distanceM: Double) -> Double {
        var low = 0
        var high = cumulativeM.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if cumulativeM[mid] <= distanceM { low = mid } else { high = mid }
        }
        return Self.bearingDeg(from: route[low], to: route[high])
    }

    /// **The odometer: along-route distance with the flown stretches taken out**
    /// (Chiu 2026-09-02).
    ///
    /// The film's kilometres are the **local journey**. On `auckland-crossing` the
    /// HUD read 8,755 km before the trip had started and 9,024 km at the end —
    /// 97% of it a flight — which is not a number anyone drove. The flight's own
    /// distance is not deleted: it appears exactly once, on the Journey Card,
    /// labelled as the flight.
    ///
    /// Subtracts each crossing's covered part rather than clamping at its start,
    /// so the readout **holds still** while the aircraft is in the air and resumes
    /// climbing on landing — which is what "this is what you travelled on the
    /// ground" looks like frame by frame.
    ///
    /// The same shape as `CameraPathCore.localDistanceM`, which the duration plan
    /// already uses for the whole trip; this is its per-instant form.
    public func traveledLocalDistanceM(atTime time: Double) -> Double {
        let travelled = traveledDistanceM(atTime: time)
        let flown = crossings.reduce(0.0) { total, crossing in
            total + min(max(travelled - crossing.fromM, 0), crossing.distanceM)
        }
        return max(travelled - flown, 0)
    }
}
