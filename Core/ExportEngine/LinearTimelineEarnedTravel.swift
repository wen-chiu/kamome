import Foundation
import KamomeConfig

/// **Travel lasts as long as its windows need, and no longer** (ADR file
/// 2026-09-28, Chiu on his New Zealand film: *「車子一直跑浪費一堆時間」*).
///
/// `RecapDurationPlan` prices the film from its stops and leaves travel a fixed
/// share of the body, because it is a story decision and cannot see the map.
/// The camera then spends that share however little ground it has to show: a
/// road trip framed wide crossed 5.7 windows in 80 s (Iceland, desk). So once
/// the camera exists, its travel is measured in route windows, the film is
/// shortened by the seconds `travel_pacing.windows_per_s` does not need, and the
/// camera is built again on the shorter clock. The stops keep every second
/// the plan gave them. The film never gets longer than the plan, so the export
/// sheet's estimate stays an upper bound.
extension LinearTimeline {
    /// Every crossing arc still holds its subject inside the safe zone on this
    /// clock — `confine` would move none of its frames. A shorter clock speeds
    /// the vehicle through the landing, and the arc is sized for the old one:
    /// Ishigaki's reached 80.5 % against an 80 % zone (`RecapCrossingArcTests`),
    /// so such a rebuild is refused and the film keeps the clock that held.
    static func arcsHoldTheirSubject(_ path: CameraPath, config: TrackingConfig.Export) -> Bool {
        let step = 1.0 / Double(config.fps)
        for arc in path.arcs {
            for time in stride(from: arc.startS, through: arc.endS, by: step) {
                let framed = arc.frame(atTime: time)
                let confined = CameraPath.confine(framed, around: path.position(atTime: time), config: config)
                guard abs(confined.centerLat - framed.centerLat) < 1e-9,
                      abs(confined.centerLon - framed.centerLon) < 1e-9 else { return false }
            }
        }
        return true
    }

    /// Travel seconds and the route windows crossed in them, read off `path`'s
    /// own clock at each stretch's framing. Crossings and reframe waits are not
    /// travel: both have fixed beats of their own.
    static func travelWindows(of path: CameraPath) -> (seconds: Double, windows: Double) {
        path.timeline.reduce(into: (seconds: 0.0, windows: 0.0)) { sum, entry in
            guard case let .travel(fromM, toM) = entry.phase, toM > fromM, entry.endS > entry.startS else { return }
            sum.seconds += entry.endS - entry.startS
            let spanM = path.cameraFrame(atTime: (entry.startS + entry.endS) / 2).spanM
            if spanM > 0 { sum.windows += (toM - fromM) / spanM }
        }
    }

    /// `first`, or the same film rebuilt on a clock that gives the road only
    /// what `windows_per_s` needs, and gives the stops back, out of what the road
    /// gave up, the seconds the plan asked for and `cappedHolds` took (Chiu
    /// 2026-09-29: 兩者都要). Never longer than the plan. **The framing is `first`'s, frozen**:
    /// the rebuild is handed its span and areas and only lays out a new clock.
    /// Re-deciding them on a shorter clock made more areas brief and split
    /// Iceland's one area into six, whose zoom beats ate the road they saved.
    ///
    /// The plan prices a stop's dwell and then adds the park ramps around it, so
    /// the stops ask for more than `max_hold_fraction` of the film and
    /// `CameraPath.cappedHolds` scaled every one down (about 12 % on New
    /// Zealand). The rebuild's fraction is chosen to land on what they asked.
    /// A few passes, because the clock's rounding moves the windows slightly.
    static func earningTravel(
        _ first: CameraPath, plan: RecapDurationPlan?, stopHoldsS: [Double], config: TrackingConfig.Export,
        rebuild: (_ totalS: Double, _ config: TrackingConfig.Export, _ framing: CameraPath.Framing) -> CameraPath?
    ) -> CameraPath {
        guard plan != nil, config.travelPacing.isEnabled else { return first }
        let frameS = 1.0 / Double(config.fps)
        func heldS(_ path: CameraPath) -> Double { path.holds.reduce(0) { $0 + $1.endS - $1.startS } }
        let askedS = stopHoldsS.reduce(0, +)
        // The film seconds outside the window the stops are capped against:
        // measured off the first build, where a capped sum is exactly the cap.
        let capped = askedS > heldS(first) + frameS
        let outsideS = first.durationS - heldS(first) / max(config.maxHoldFraction, 0.01)
        var path = first
        for _ in 0..<3 {
            let travel = travelWindows(of: path)
            let excessS = max(travel.seconds - travel.windows / config.travelPacing.windowsPerS, 0)
            // The stops take back what they were owed out of what the road gives
            // up, and no more: the film is never longer than the plan, which is
            // what its length ceiling was fitted to (ADR 2026-09-27).
            let owedS = min(max(askedS - heldS(path), 0), excessS)
            let totalS = max(path.durationS - excessS + owedS, config.totalDurationMinS)
            guard excessS > frameS, abs(totalS - path.durationS) > frameS || owedS > frameS else { break }
            let windowS = totalS - outsideS
            let targetS = heldS(path) + owedS
            guard !capped || windowS > targetS else { break }
            let fraction = capped ? targetS / windowS : 1
            guard let next = rebuild(totalS, config.withMaxHoldFraction(fraction), first.framing),
                  arcsHoldTheirSubject(next, config: config) else { break }
            path = next
        }
        return path
    }
}
