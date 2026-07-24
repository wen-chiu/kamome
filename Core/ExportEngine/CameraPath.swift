import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// §4.5 step 1: the deterministic camera path for the recap video.
///
/// The **vehicle** travels the full-trip polyline speed-warped so the video
/// always lasts `export.target_duration_s` regardless of trip length. At each
/// stop it holds for `export.stop_hold_s` (the photo card moment); travel legs
/// between stops get smoothstep easing, so it decelerates into every hold and
/// accelerates out of it. Holds pin to the route point nearest the stop, not
/// the dwell center, so the vehicle never jumps off the polyline. When holds
/// would eat more than `export.max_hold_fraction` of the video, they shrink
/// proportionally — travel time never reaches zero.
///
/// The **camera** (`cameraFrame`) is a separate concern from the vehicle
/// (`position`): the title/end windows sit wide on the whole trip (the
/// establishing / closing shots), and the body zooms into a close, optionally
/// heading-up follow-cam locked on the vehicle (prototype §2.3 — "the vehicle
/// is the subject," not a dot on a wide map). Wide↔close eases over
/// `export.zoom_transition_s` at each card boundary. During wide shots the
/// camera centers on the trip, not the vehicle, so the whole route is framed
/// while the vehicle sits small in its real place — which is why camera and
/// vehicle are two outputs, not one.
///
/// Pure value math over Doubles: the same trip and config always produce the
/// same frames, which is what the golden-frame gate tests rely on.
public struct CameraPath {
    public struct Point: Equatable {
        public let lat: Double
        public let lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    /// The vehicle (the subject): where the marker is drawn and which way it
    /// faces. Projected through the snapshot by the compositor.
    public struct Position: Equatable {
        public let lat: Double
        public let lon: Double
        /// Direction of travel in degrees, 0 = north, clockwise. The route
        /// tangent while travelling; the approach heading while holding.
        public let heading: Double
        /// Index into the `stops` array passed at init while the vehicle is
        /// holding there, else nil. Drives the photo-card animation.
        public let holdingStopIndex: Int?
    }

    /// What the base-map snapshot is taken at (§4.5 step 2). `bearing` rotates
    /// the map heading-up; `spanM` is the horizontal ground span. Distinct from
    /// `Position`: in wide shots the camera frames the trip while the vehicle
    /// sits off-center in its real location.
    public struct CameraFrame: Equatable {
        public let centerLat: Double
        public let centerLon: Double
        public let spanM: Double
        public let bearing: Double
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

    // Camera framing (cameraFrame). The wide establishing/closing shots frame
    // the whole trip; the body zooms into `closeSpanM` on the vehicle.
    private let closeSpanM: Double
    private let wideSpanM: Double
    private let tripCenterLat: Double
    private let tripCenterLon: Double
    private let zoomTransitionS: Double
    private let followHeadingUp: Bool
    private let bodyStartS: Double
    private let bodyEndS: Double

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

        // Establishing-shot framing, all derived from the route geometry.
        let bounds = Self.bounds(of: route)
        tripCenterLat = (bounds.minLat + bounds.maxLat) / 2
        tripCenterLon = (bounds.minLon + bounds.maxLon) / 2
        closeSpanM = config.cameraSpanM
        wideSpanM = max(
            config.cameraSpanM,
            Self.fittingSpanM(bounds: bounds, config: config) * config.wideSpanPadding
        )
        zoomTransitionS = config.zoomTransitionS
        followHeadingUp = config.followHeadingUp
        bodyStartS = min(config.titleCardS, config.targetDurationS)
        bodyEndS = max(bodyStartS, config.targetDurationS - config.endCardS)
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
        return Position(
            lat: point.lat, lon: point.lon,
            heading: heading(atDistance: distanceM),
            holdingStopIndex: holdIndex
        )
    }

    /// The base-map framing at `time`: wide over the whole trip during the
    /// title/end windows, close on the vehicle through the body, eased between.
    public func cameraFrame(atTime time: Double) -> CameraFrame {
        let vehicle = position(atTime: time)
        let closeness = Self.smoothstep(framing(atTime: time))
        let spanM = wideSpanM + (closeSpanM - wideSpanM) * closeness
        // Wide → center the trip so the whole route is in frame; close → center
        // the vehicle. Small lat/lon lerps are safe (no antimeridian trips).
        let centerLat = tripCenterLat + (vehicle.lat - tripCenterLat) * closeness
        let centerLon = tripCenterLon + (vehicle.lon - tripCenterLon) * closeness
        let bearing = followHeadingUp ? Self.angleLerp(from: 0, to: vehicle.heading, fraction: closeness) : 0
        return CameraFrame(centerLat: centerLat, centerLon: centerLon, spanM: spanM, bearing: bearing)
    }

    /// Closeness at `time`: 0 = wide establishing/closing shot, 1 = close
    /// follow-cam. Wide through the card windows, ramping to close over
    /// `zoom_transition_s` just inside each boundary.
    private func framing(atTime time: Double) -> Double {
        guard time > bodyStartS, time < bodyEndS else { return 0 }
        let transition = max(zoomTransitionS, 1e-6)
        let rampIn = (time - bodyStartS) / transition
        let rampOut = (bodyEndS - time) / transition
        return min(1, min(rampIn, rampOut))
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

    /// Heading (deg) of the route segment bracketing `distanceM` — the vehicle
    /// faces the way it is travelling. Binary search mirrors `coordinate`.
    private func heading(atDistance distanceM: Double) -> Double {
        var low = 0
        var high = cumulativeM.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if cumulativeM[mid] <= distanceM { low = mid } else { high = mid }
        }
        return Self.bearingDeg(from: route[low], to: route[high])
    }

    /// Ease-in/out (§4.5): zero velocity at both ends of every travel leg.
    private static func smoothstep(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

// MARK: - Framing geometry (pure, deterministic)

private extension CameraPath {
    struct Bounds {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
    }

    static func bounds(of route: [Point]) -> Bounds {
        var minLat = route[0].lat, maxLat = route[0].lat
        var minLon = route[0].lon, maxLon = route[0].lon
        for point in route {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        return Bounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    /// Horizontal span that fits the whole route into the (portrait) frame:
    /// wide enough for the east-west extent, and for the north-south extent
    /// once scaled by the frame's aspect (vertical span = spanM · h/w).
    static func fittingSpanM(bounds: Bounds, config: TrackingConfig.Export) -> Double {
        let midLat = (bounds.minLat + bounds.maxLat) / 2
        let lonExtentM = Geo.distanceM(latA: midLat, lonA: bounds.minLon, latB: midLat, lonB: bounds.maxLon)
        let latExtentM = Geo.distanceM(latA: bounds.minLat, lonA: bounds.minLon, latB: bounds.maxLat, lonB: bounds.minLon)
        let aspect = Double(config.frameWidthPx) / Double(config.frameHeightPx)
        return max(lonExtentM, latExtentM * aspect)
    }

    /// Planar bearing (deg, 0 = north, clockwise) — `atan2(east, north)` with a
    /// cos(lat) correction. Enough for a follow-cam at recap zoom; degenerate
    /// (coincident) points face north.
    static func bearingDeg(from start: Point, to end: Point) -> Double {
        let meanLatRad = (start.lat + end.lat) / 2 * .pi / 180
        let east = (end.lon - start.lon) * cos(meanLatRad)
        let north = end.lat - start.lat
        guard east != 0 || north != 0 else { return 0 }
        let deg = atan2(east, north) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    /// Interpolate along the shortest arc from `start` to `end` (degrees), so a
    /// heading near 360° eases toward 0° the short way, not backwards.
    static func angleLerp(from start: Double, to end: Double, fraction: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let result = (start + delta * fraction).truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
