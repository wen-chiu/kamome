import Foundation
import KamomeConfig

/// The travel camera (Chiu 2026-08-01): a **dead-zone dolly**, not a viewport
/// that recentres on a cursor.
///
/// **What it replaces and why.** The camera used to be framed per *act* — a
/// stretch of route between two big leaps, fitted to its own bounds and floored
/// at `camera_span_m`. Framing therefore came from data shape while timing came
/// from the clock, and nothing reconciled them: on a real multi-day import the
/// acts collapsed onto the 1,500 m floor and the camera crossed 110 km between
/// them, replacing the screen ~24 times a second. Four separate-looking symptoms
/// — frozen opening, stutter on inferred legs, strobe, wrong end reveal — were
/// that one fault.
///
/// **The rule this encodes.** Two consecutive frames must always share meaningful
/// geography. So the camera is never *placed*; it is only ever *moved*, from
/// wherever it already was, at a bounded rate. Continuity beats composition: a
/// slightly off-centre subject is always better than a jump that costs the viewer
/// their mental map.
///
/// **How it behaves.**
/// - A dead zone covers the middle `camera_dead_zone_fraction` of the frame.
///   While the subject is inside it the camera does not move *at all*.
/// - Past that edge the camera accelerates after it on a critically damped
///   spring — it leans into the move and settles out of it, like a dolly, and
///   (being critically damped) never overshoots and hunts.
/// - Span is fixed for the whole body. No zoom, no rotation while travelling.
///
/// **Inertia lives here, in the simulation** — never as a smoothing pass over a
/// finished track. A filter applied afterwards would push the camera while the
/// subject sits inside the dead zone, which is precisely the "completely still"
/// guarantee, and would bleed momentum across a discontinuity.
///
/// The simulation is sequential (frame N depends on N−1) but runs **once** at
/// build time; the resulting track is stored and read randomly, so
/// `CameraPath.cameraFrame(atTime:)` stays pure, deterministic and
/// random-access — which the snapshot cache and the render loop's out-of-order
/// prefetch both rely on.
enum FollowCamera {
    /// Simulates the whole body and returns one frame per film frame.
    ///
    /// `subject` is the leading edge of the journey, sampled per frame — already
    /// speed-warped by `CameraPath`, so time is distributed in proportion to
    /// distance. That is what makes the pan rate uniform for free: every leg,
    /// motorway or inferred straight line, is crossed at the same fraction of a
    /// window per second, so no leg needs special handling to stay watchable.
    static func track(
        subject: [CameraPath.Point],
        parked: [Bool],
        routeBounds: CameraPath.Bounds,
        spanM: Double,
        config: TrackingConfig.Export
    ) -> [CameraPath.CameraFrame] {
        guard let first = subject.first else { return [] }
        let aspect = Double(config.frameHeightPx) / Double(config.frameWidthPx)
        // Half-extents of the dead zone, in ground metres.
        let halfWidthM = spanM / 2 * config.cameraDeadZoneFraction
        let halfHeightM = spanM * aspect / 2 * config.cameraDeadZoneFraction

        // A local flat projection about the route's own latitude: exact enough at
        // recap scale, and deterministic, which the golden-frame gates need.
        let referenceLat = subject.reduce(0.0) { $0 + $1.lat } / Double(subject.count)
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = 111_320.0 * cos(referenceLat * .pi / 180)

        let dt = 1.0 / Double(config.fps)
        let omega = max(config.cameraResponsiveness, 0.01)

        // **World bounds clamp** — the side-scroller idiom. The camera is not
        // allowed to frame ground the journey never visits, so it stays inside
        // the route's own extent, inset by half a window.
        //
        // Two things fall out of it, and both matter. A short trip whose window
        // is wider than the whole route collapses to a single centred framing —
        // so the film opens on the *whole journey* rather than on its first
        // kilometre with half the frame empty, and the body camera is then
        // genuinely motionless. A long trip is only clamped near its two ends,
        // which is exactly where an unclamped camera would drift off into blank
        // territory ahead of the start or past the finish.
        let halfWindowLatDeg = spanM * aspect / 2 / metresPerDegreeLat
        let halfWindowLonDeg = spanM / 2 / metresPerDegreeLon
        let centreOfRouteLat = (routeBounds.minLat + routeBounds.maxLat) / 2
        let centreOfRouteLon = (routeBounds.minLon + routeBounds.maxLon) / 2
        let latRange = clampRange(
            low: routeBounds.minLat + halfWindowLatDeg,
            high: routeBounds.maxLat - halfWindowLatDeg,
            fallback: centreOfRouteLat
        )
        let lonRange = clampRange(
            low: routeBounds.minLon + halfWindowLonDeg,
            high: routeBounds.maxLon - halfWindowLonDeg,
            fallback: centreOfRouteLon
        )

        var state = SimState(
            centreLat: min(max(first.lat, latRange.low), latRange.high),
            centreLon: min(max(first.lon, lonRange.low), lonRange.high)
        )

        var frames: [CameraPath.CameraFrame] = []
        frames.reserveCapacity(subject.count)

        // The hard guarantee (Chiu 2026-08-01): the subject may never leave the
        // inner `camera_safe_zone_fraction` of the frame. It does not have to be
        // centred, but the audience must never have to chase it toward the edge.
        let constants = StepConstants(
            halfWidthM: halfWidthM, halfHeightM: halfHeightM,
            safeWidthM: spanM / 2 * config.cameraSafeZoneFraction,
            safeHeightM: spanM * aspect / 2 * config.cameraSafeZoneFraction,
            metresPerDegreeLat: metresPerDegreeLat, metresPerDegreeLon: metresPerDegreeLon,
            latRange: latRange, lonRange: lonRange, dt: dt, omega: omega, spanM: spanM
        )

        for (index, point) in subject.enumerated() {
            let isParked = index < parked.count && parked[index]
            let stepped = step(state, point: point, parked: isParked, constants: constants)
            state = stepped.state
            frames.append(stepped.frame)
        }
        return frames
    }

    /// The dolly's carried-over motion: frame N depends on N−1, which is why the
    /// simulation runs once at build time rather than being recomputed live.
    private struct SimState {
        var centreLat: Double
        var centreLon: Double
        /// Metres per second, in ground space — the inertia, and the reason the
        /// camera leans into a move.
        var velocityEast = 0.0
        var velocityNorth = 0.0
    }

    /// Everything about the trip and the frame that does not change per step —
    /// computed once in `track` and threaded through so `step` stays a pure
    /// function of (state, subject) for exactly one frame.
    private struct StepConstants {
        let halfWidthM: Double
        let halfHeightM: Double
        let safeWidthM: Double
        let safeHeightM: Double
        let metresPerDegreeLat: Double
        let metresPerDegreeLon: Double
        let latRange: (low: Double, high: Double)
        let lonRange: (low: Double, high: Double)
        let dt: Double
        let omega: Double
        let spanM: Double
    }

    /// One frame of the simulation: given where the dolly was, where the
    /// subject now is, and whether it is parked, returns where the dolly is now.
    private static func step(
        _ state: SimState, point: CameraPath.Point, parked: Bool, constants: StepConstants
    ) -> (state: SimState, frame: CameraPath.CameraFrame) {
        var state = state
        // **Parked: the camera is frozen outright.** A stop is a static beat by
        // product rule, and letting the spring settle through it was not
        // harmless — a pin drifting a few pixels re-triggered the stop card's
        // above/below decision mid-scene. The subject is not moving here, so
        // there is nothing to follow anyway.
        if parked {
            state.velocityEast = 0
            state.velocityNorth = 0
            let frame = CameraPath.CameraFrame(
                centerLat: state.centreLat, centerLon: state.centreLon, spanM: constants.spanM, bearing: 0
            )
            return (state, frame)
        }

        // How far the subject sits from the frame centre, in metres.
        let offsetEastM = (point.lon - state.centreLon) * constants.metresPerDegreeLon
        let offsetNorthM = (point.lat - state.centreLat) * constants.metresPerDegreeLat

        // Only the part that has escaped the dead zone is an error worth
        // correcting. Inside the box this is exactly zero, so the spring is
        // silent and the camera is genuinely still — not slowly creeping.
        let errorEastM = offsetEastM - min(max(offsetEastM, -constants.halfWidthM), constants.halfWidthM)
        let errorNorthM = offsetNorthM - min(max(offsetNorthM, -constants.halfHeightM), constants.halfHeightM)

        // Critically damped spring: a = ω²·error − 2ω·v. Settles without
        // overshoot, so the camera never rubber-bands past the subject and
        // pulls back — which would read as a wobble on every straight road.
        let omega = constants.omega, dt = constants.dt
        state.velocityEast += (omega * omega * errorEastM - 2 * omega * state.velocityEast) * dt
        state.velocityNorth += (omega * omega * errorNorthM - 2 * omega * state.velocityNorth) * dt

        // Semi-implicit integration (velocity first, then position): stable at
        // the ω·dt this runs at, and it keeps the camera from lagging a frame
        // behind its own acceleration.
        state.centreLon += state.velocityEast * dt / constants.metresPerDegreeLon
        state.centreLat += state.velocityNorth * dt / constants.metresPerDegreeLat

        // Held at the world's edge, the spring would keep winding up and then
        // fire the moment the subject turned back. Killing the velocity it
        // cannot spend keeps the camera dead still against the boundary.
        //
        // **The world clamp yields to the subject.** Not framing unvisited
        // ground is a preference; keeping the subject comfortably in frame is
        // not. At a route's extremes the two disagree — the clamp wants to stop
        // while the journey keeps going — and taking the clamp anyway pushed
        // the car out to the hard safe-zone limit, where it sat in the corner
        // of frame. So the clamp is applied only while the subject stays inside
        // the dead zone; past that the camera follows and shows a little
        // ground beyond the trip's own box, which nobody notices.
        let worldLat = min(max(state.centreLat, constants.latRange.low), constants.latRange.high)
        let worldLon = min(max(state.centreLon, constants.lonRange.low), constants.lonRange.high)
        if worldLat != state.centreLat,
           abs(point.lat - worldLat) * constants.metresPerDegreeLat <= constants.halfHeightM {
            state.velocityNorth = 0
            state.centreLat = worldLat
        }
        if worldLon != state.centreLon,
           abs(point.lon - worldLon) * constants.metresPerDegreeLon <= constants.halfWidthM {
            state.velocityEast = 0
            state.centreLon = worldLon
        }

        // **The constraint wins.** Applied last, so it overrides both the
        // spring's lag and the world clamp: on a fast leg the dolly simply
        // cannot accelerate hard enough, and at the route's ends the world
        // clamp would rather sit still than follow. Either way the subject
        // would drift into the margin, so here the camera is dragged the
        // minimum distance that puts it back on the safe boundary. Smoothness
        // is what gets sacrificed, and that is the right way round.
        state.centreLon = confine(
            centre: state.centreLon, subject: point.lon,
            halfExtentM: constants.safeWidthM, metresPerDegree: constants.metresPerDegreeLon
        )
        state.centreLat = confine(
            centre: state.centreLat, subject: point.lat,
            halfExtentM: constants.safeHeightM, metresPerDegree: constants.metresPerDegreeLat
        )

        let frame = CameraPath.CameraFrame(
            centerLat: state.centreLat, centerLon: state.centreLon, spanM: constants.spanM, bearing: 0
        )
        return (state, frame)
    }

    /// Pulls `centre` just far enough that `subject` sits no further than
    /// `halfExtentM` from it. A no-op whenever the subject is already inside.
    private static func confine(
        centre: Double, subject: Double, halfExtentM: Double, metresPerDegree: Double
    ) -> Double {
        let halfExtentDeg = halfExtentM / metresPerDegree
        return min(max(centre, subject - halfExtentDeg), subject + halfExtentDeg)
    }

    /// A clamp range that degenerates to a single value when the window is wider
    /// than the world — the "whole route already fits" case.
    private static func clampRange(
        low: Double, high: Double, fallback: Double
    ) -> (low: Double, high: Double) {
        low > high ? (fallback, fallback) : (low, high)
    }
}
