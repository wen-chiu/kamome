import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// §4.5 step 1: the deterministic camera path for the recap video.
///
/// The camera travels the full-trip polyline speed-warped so the video always
/// lasts `export.target_duration_s` regardless of trip length. At each stop it
/// holds for `export.stop_hold_s` (the photo card moment); travel legs between
/// stops get smoothstep easing, so the camera decelerates into every hold and
/// accelerates out of it. Holds pin to the route point nearest the stop, not
/// the dwell center, so the camera never jumps off the polyline. When holds
/// would eat more than `export.max_hold_fraction` of the video, they shrink
/// proportionally — travel time never reaches zero.
///
/// Pure value math over Doubles: the same trip and config always produce the
/// same frame positions, which is what the golden-frame gate tests rely on.
public struct CameraPath {
    public struct Point: Equatable {
        public let lat: Double
        public let lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    public struct Position: Equatable {
        public let lat: Double
        public let lon: Double
        /// Index into the `stops` array passed at init while the camera is
        /// holding there, else nil. Drives the photo-card animation.
        public let holdingStopIndex: Int?
    }

    private enum Phase {
        case travel(fromM: Double, toM: Double)
        case hold(stopIndex: Int, atM: Double)
    }

    private struct TimelineEntry {
        let startS: Double
        let endS: Double
        let phase: Phase
    }

    public struct Hold: Equatable {
        public let stopIndex: Int
        public let startS: Double
        public let endS: Double
    }

    public let frameCount: Int
    public let durationS: Double

    /// Hold windows in video time, in playback order — what OverlayTimeline
    /// anchors stop cards to (decisions.md 2026-07-17: overlay moments are
    /// timeline events, not per-frame reads of the camera's hold state).
    public var holds: [Hold] {
        timeline.compactMap { entry in
            guard case let .hold(stopIndex, _) = entry.phase else { return nil }
            return Hold(stopIndex: stopIndex, startS: entry.startS, endS: entry.endS)
        }
    }

    private let fps: Int
    private let route: [Point]
    private let cumulativeM: [Double]
    private let timeline: [TimelineEntry]

    /// Fails on degenerate input (fewer than two points or zero length) —
    /// the phantom-trip guard keeps such trips out of the DB, so a caller
    /// asking anyway has a bug upstream.
    public init?(route: [Point], stops: [Point], config: TrackingConfig.Export) {
        guard route.count >= 2 else { return nil }
        var cumulative = [0.0]
        cumulative.reserveCapacity(route.count)
        for index in 1..<route.count {
            let step = Geo.distanceM(
                latA: route[index - 1].lat, lonA: route[index - 1].lon,
                latB: route[index].lat, lonB: route[index].lon
            )
            cumulative.append(cumulative[index - 1] + step)
        }
        guard let totalM = cumulative.last, totalM > 0 else { return nil }

        let anchors = Self.stopAnchors(route: route, cumulativeM: cumulative, stops: stops)

        self.route = route
        self.cumulativeM = cumulative
        timeline = Self.buildTimeline(anchors: anchors, totalM: totalM, config: config)
        self.fps = config.fps
        durationS = config.targetDurationS
        frameCount = Int((config.targetDurationS * Double(config.fps)).rounded())
    }

    /// Anchor each stop to its nearest route vertex, ordered along the path.
    private static func stopAnchors(
        route: [Point],
        cumulativeM: [Double],
        stops: [Point]
    ) -> [(stopIndex: Int, distanceM: Double)] {
        stops.enumerated().map { index, stop in
            var bestVertex = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (vertex, point) in route.enumerated() {
                let distance = Geo.distanceM(latA: stop.lat, lonA: stop.lon, latB: point.lat, lonB: point.lon)
                if distance < bestDistance {
                    bestDistance = distance
                    bestVertex = vertex
                }
            }
            return (index, cumulativeM[bestVertex])
        }
        .sorted { $0.distanceM < $1.distanceM }
    }

    /// Time budget: holds first (capped at `max_hold_fraction`), the rest is
    /// travel, split across legs in proportion to leg distance.
    private static func buildTimeline(
        anchors: [(stopIndex: Int, distanceM: Double)],
        totalM: Double,
        config: TrackingConfig.Export
    ) -> [TimelineEntry] {
        let targetS = config.targetDurationS
        var holdS = config.stopHoldS
        if !anchors.isEmpty {
            holdS = min(holdS, targetS * config.maxHoldFraction / Double(anchors.count))
        }
        let travelS = targetS - holdS * Double(anchors.count)

        var timeline: [TimelineEntry] = []
        var clock = 0.0
        var legStartM = 0.0
        for anchor in anchors {
            let legM = max(0, anchor.distanceM - legStartM)
            let legS = travelS * legM / totalM
            timeline.append(
                .init(startS: clock, endS: clock + legS, phase: .travel(fromM: legStartM, toM: anchor.distanceM))
            )
            clock += legS
            timeline.append(
                .init(startS: clock, endS: clock + holdS, phase: .hold(stopIndex: anchor.stopIndex, atM: anchor.distanceM))
            )
            clock += holdS
            legStartM = anchor.distanceM
        }
        timeline.append(.init(startS: clock, endS: targetS, phase: .travel(fromM: legStartM, toM: totalM)))
        return timeline
    }

    public func position(atFrame frame: Int) -> Position {
        position(atTime: Double(frame) / Double(fps))
    }

    public func position(atTime time: Double) -> Position {
        let (distanceM, holdIndex) = state(atTime: time)
        let point = coordinate(atDistance: distanceM)
        return Position(lat: point.lat, lon: point.lon, holdingStopIndex: holdIndex)
    }

    /// Along-route distance covered at `time` — the frame renderer's traveled
    /// polyline ends here.
    public func traveledDistanceM(atTime time: Double) -> Double {
        state(atTime: time).distanceM
    }

    /// Route vertices already passed at `time`, closed with the interpolated
    /// head point, ready for the traveled-polyline stroke (§4.5 step 2).
    public func routePrefix(atTime time: Double) -> [Point] {
        let distanceM = traveledDistanceM(atTime: time)
        var prefix: [Point] = []
        for (index, vertexM) in cumulativeM.enumerated() where vertexM < distanceM {
            prefix.append(route[index])
        }
        prefix.append(coordinate(atDistance: distanceM))
        return prefix
    }

    private func state(atTime time: Double) -> (distanceM: Double, holdIndex: Int?) {
        let clamped = min(max(time, 0), durationS)
        // The timeline is a handful of entries per stop — linear scan is fine.
        let entry = timeline.last(where: { $0.startS <= clamped }) ?? timeline[0]
        switch entry.phase {
        case let .hold(stopIndex, atM):
            return (atM, stopIndex)
        case let .travel(fromM, toM):
            let span = entry.endS - entry.startS
            let progress = span > 0 ? (clamped - entry.startS) / span : 1
            let eased = Self.smoothstep(min(max(progress, 0), 1))
            return (fromM + (toM - fromM) * eased, nil)
        }
    }

    private func coordinate(atDistance distanceM: Double) -> Point {
        var low = 0
        var high = cumulativeM.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if cumulativeM[mid] <= distanceM { low = mid } else { high = mid }
        }
        let spanM = cumulativeM[high] - cumulativeM[low]
        guard spanM > 0 else { return route[low] }
        let fraction = min(max((distanceM - cumulativeM[low]) / spanM, 0), 1)
        return Point(
            lat: route[low].lat + (route[high].lat - route[low].lat) * fraction,
            lon: route[low].lon + (route[high].lon - route[low].lon) * fraction
        )
    }

    /// Ease-in/out (§4.5): zero velocity at both ends of every travel leg.
    private static func smoothstep(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }
}
