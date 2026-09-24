import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **The body camera over several areas** (ADR 2026-09-24) — the half of
/// `CameraPathAreas` that turns an `AreaPlan` into frames: one dead-zone dolly
/// per area, joined by reframe moves and crossing arcs.
extension CameraPath {
    /// The journey clock and the body camera, built together because the camera
    /// is simulated over the clock and the reframe moves read the simulated track.
    struct BodyCamera {
        let timeline: [TimelineEntry]
        let track: [CameraFrame]
        let reframeArcs: [Arc]
    }

    /// What the journey's clock is built from: the stops, their holds, the
    /// crossings, and the window the journey plays in.
    struct Journey {
        let anchors: [(stopIndex: Int, distanceM: Double)]
        let totalM: Double
        let stopHoldsS: [Double]?
        let crossings: [Crossing]
        let startS: Double
        let endS: Double
    }

    /// Builds the journey timeline and the body camera — through the one-span
    /// path, unchanged, when `areaPlan` is nil. `request.journeyTimeline` is
    /// ignored: the timeline is what this builds.
    static func bodyCamera(_ request: TrackRequest, journey: Journey, areaPlan: AreaPlan?) -> BodyCamera {
        let built = buildTimelineWithReframes(
            anchors: journey.anchors, totalM: journey.totalM, config: request.config,
            stopHoldsS: journey.stopHoldsS, crossings: journey.crossings,
            startS: journey.startS, targetS: journey.endS,
            reframes: areaPlan?.reframes ?? [], areas: areaPlan
        )
        let timed = TrackRequest(
            route: request.route, cumulativeM: request.cumulativeM, journeyTimeline: built.entries,
            frameCount: request.frameCount, fps: request.fps, durationS: request.durationS,
            spanM: request.spanM, config: request.config
        )
        let track: [CameraFrame]
        if let areaPlan {
            let startsS = areaStartTimesS(
                plan: areaPlan, reframes: built.reframes, timeline: built.entries, durationS: request.durationS
            )
            track = simulatedAreaTrack(timed, plan: areaPlan, startsS: startsS)
        } else {
            track = simulatedTrack(timed)
        }
        return BodyCamera(
            timeline: built.entries, track: track,
            reframeArcs: reframeMoves(built.reframes, track: track, fps: request.fps, config: request.config)
        )
    }

    /// Film time at which each area takes the frame: the first at 0, one after a
    /// reframe at the start of its beat, one after a crossing when the crossing
    /// lands (the arc carries the frame across, from the dolly it left to the
    /// one it lands on).
    static func areaStartTimesS(
        plan: AreaPlan, reframes: [ReframeWindow], timeline: [TimelineEntry], durationS: Double
    ) -> [Double] {
        var windows = reframes.makeIterator()
        return plan.areas.enumerated().map { index, area in
            guard index > 0 else { return 0 }
            if !area.followsCrossing, let window = windows.next() { return window.startS }
            return time(atDistance: area.fromM, timeline: timeline, durationS: durationS)
        }
    }

    /// The body camera over several areas: one dead-zone dolly per area, each
    /// started fresh when its area takes the frame. Every seam between two runs
    /// is covered by a move — a reframe beat or a crossing arc — so the dolly is
    /// never seen to restart.
    static func simulatedAreaTrack(_ request: TrackRequest, plan: AreaPlan, startsS: [Double]) -> [CameraFrame] {
        let fps = Double(request.fps)
        // A reframe's area takes the frame at the first frame **inside** its beat,
        // so every frame before the beat is still the old dolly's; a crossing's at
        // the frame the arc lands on, which is the one it reads (`buildArcs`).
        let startFrames = zip(plan.areas, startsS).map { area, start in
            Int((start * fps).rounded(area.followsCrossing ? .toNearestOrAwayFromZero : .up))
        }
        var track: [CameraFrame] = []
        track.reserveCapacity(request.frameCount)
        for (index, area) in plan.areas.enumerated() {
            let first = min(max(startFrames[index], 0), request.frameCount)
            let last = index + 1 < startFrames.count
                ? min(max(startFrames[index + 1], first), request.frameCount) : request.frameCount
            guard last > first else { continue }
            let sampled = (first..<last).map { sample(frame: $0, request: request) }
            track += FollowCamera.track(
                subject: sampled.map(\.point), parked: sampled.map(\.parked),
                routeBounds: area.bounds, spanM: area.spanM, config: request.config
            )
        }
        return track
    }

    /// The subject at one film frame, and whether it is parked there.
    static func sample(frame: Int, request: TrackRequest) -> (point: Point, parked: Bool) {
        let time = Double(frame) / Double(request.fps)
        let clamped = min(max(time, 0), request.durationS)
        let entry = request.journeyTimeline.last(where: { $0.startS <= clamped }) ?? request.journeyTimeline[0]
        let distanceM = distance(atTime: time, timeline: request.journeyTimeline, durationS: request.durationS)
        let parked: Bool
        if case .hold = entry.phase { parked = true } else { parked = false }
        return (coordinate(atDistance: distanceM, route: request.route, cumulativeM: request.cumulativeM), parked)
    }

    /// The move played over each reframe beat: from the dolly the stop was
    /// presented in to the settled dolly of the next area, while the vehicle
    /// waits. A pure zoom through `containedLerp` when the wider frame already
    /// contains the tighter one, and through an apex containing both otherwise —
    /// the crossing arc's primitive, so it is contained by construction either way.
    static func reframeMoves(
        _ windows: [ReframeWindow], track: [CameraFrame], fps: Int, config: TrackingConfig.Export
    ) -> [Arc] {
        guard !track.isEmpty else { return [] }
        func frame(atFrame index: Int) -> CameraFrame { track[min(max(index, 0), track.count - 1)] }
        return windows.map { window in
            // The last frame before the beat — the old area's dolly (`simulatedAreaTrack`).
            let source = frame(atFrame: Int((window.startS * Double(fps)).rounded(.up)) - 1)
            let destination = frame(atFrame: Int((window.endS * Double(fps)).rounded()))
            let wider = source.spanM >= destination.spanM ? source : destination
            let hull = containingFrame([source, destination], padding: 1, config: config)
            let apex = hull.spanM <= wider.spanM * (1 + 1e-9)
                ? wider : apexFrame(source: source, destination: destination, config: config)
            // Split the beat in proportion to the zoom each half performs, so the
            // apparent rate of zoom is one constant across the whole move.
            let out = log(apex.spanM / max(source.spanM, 1e-9))
            let back = log(apex.spanM / max(destination.spanM, 1e-9))
            let share = out + back > 0 ? out / (out + back) : 0.5
            return Arc(
                startS: window.startS, endS: window.endS, source: source, apex: apex,
                destination: destination, holdUntilS: window.startS + (window.endS - window.startS) * share
            )
        }
    }
}
