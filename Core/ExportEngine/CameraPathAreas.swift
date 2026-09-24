import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **The body is framed area by area, not at one span for the whole trip**
/// (ADR 2026-09-24 — Chiu reopened the 2026-08-02 per-segment line by name).
///
/// ## Why one span per trip failed
///
/// The body span used to be `established / target_zoom_ratio`, where
/// `established` is the whole journey's bounding box padded — so every film
/// framed every stop at **0.60 × the trip's extent** (measured on all seven
/// fixtures, `Docs/camera-arcs.md` §5). A bounding box belongs to its single
/// farthest point: one out-of-town airport or one day trip sized the frame of
/// every town loop in the film. On Chiu's Miyakojima dump the body was 19.0 km
/// wide while the arrival day's stops sat inside 1.5 × 0.6 km.
///
/// ## What replaces it
///
/// The journey is cut at every stop into **stretches**; consecutive stretches
/// share an **area** while each of them is framed within
/// `camera_area_split_ratio` of what it would ask for alone. Each area then gets
/// the old rule **applied to itself** — its own extent × `wide_span_padding` ÷
/// `target_zoom_ratio`, floored at `camera_span_m`, never wider than its own
/// establishing framing — so a trip with one area is the film it always was,
/// and the path that builds it is literally the old one (`AreaPlan.make`
/// returns nil).
///
/// ## Why this is not the act camera again
///
/// The 2026-08-02 act camera *placed* a new frame at every act, mid-motion,
/// with nothing showing the viewer the change of scale. Here:
///
/// - **A scale change is a beat of its own**, played while the vehicle waits at
///   the stop between two areas (a `.travel(m, m)` entry, the same idiom as the
///   opening's wait). The subject is stationary, so `confine` never fires and the
///   move is a pure contained zoom — the property the crossing arc's close was
///   rebuilt around on 2026-09-02.
/// - **A stop is always presented at the tighter of its two framings**: the beat
///   plays *before* the stop's scene when the next area is tighter, and *after*
///   it when the next area is wider. The scene itself never zooms — a stop is a
///   static beat by product rule (`FollowCamera.step`, parked).
/// - Within an area the camera is the same dead-zone dolly, never placed.
///
/// ## Why the travel clock is shared by screen distance
///
/// The pan floor (`camera_pan_window_fraction_per_s`) bounds how much of the
/// window the ground crosses per second. With one span it was
/// `routeDistance / (travelS × rate)`, because time was shared in proportion to
/// ground distance. Kept that way it would floor a 1.5 km town at the rate the
/// island's 130 km sets — 11.8 km on Miyakojima, which is the smudge again. So
/// travel time is shared in proportion to **ground distance ÷ area span**: the
/// window crosses at one rate everywhere, and the floor becomes one common
/// factor over every area. With one area both reduce exactly to the old formula.
extension CameraPath {
    /// One stretch of the body framed at one span.
    struct Area {
        /// Along-route metres of the area's first and last local stretch.
        let fromM: Double
        let toM: Double
        /// Local (road) metres inside the area — the pan floor's numerator.
        let localM: Double
        let bounds: Bounds
        let spanM: Double
        /// Entered by a crossing, whose arc carries the change of scale — so no
        /// reframe beat precedes it.
        let followsCrossing: Bool
    }

    /// A change of area at a stop: when the scale changes, and on which side of
    /// the stop's scene.
    struct Reframe: Equatable {
        let atM: Double
        /// True when the next area is tighter — the beat plays before the scene.
        let zoomsIn: Bool
    }

    /// A reframe beat as placed on the film clock by `buildTimeline`.
    struct ReframeWindow: Equatable {
        let startS: Double
        let endS: Double
    }

    /// The areas a film's body is framed in, and the reframes between them.
    struct AreaPlan {
        let areas: [Area]
        let reframes: [Reframe]

        /// Weighted metres for the travel clock: ground metres ÷ the span of the
        /// area they lie in. See the type's "screen distance" section.
        func screenM(fromM: Double, toM: Double) -> Double {
            guard toM > fromM else { return 0 }
            return (toM - fromM) / area(atM: (fromM + toM) / 2).spanM
        }

        var screenLocalM: Double { areas.reduce(0) { $0 + $1.localM / $1.spanM } }

        /// The area covering `distanceM`; metres before the first area (a trip
        /// that opens on its crossing) belong to the first.
        func area(atM distanceM: Double) -> Area {
            areas.last(where: { $0.fromM <= distanceM }) ?? areas[0]
        }

        /// **nil when the film has one area** — and then the caller builds the
        /// film exactly as before, through the one-span path.
        ///
        /// Two merges run to a fixed point, each only ever lowering the count, so
        /// this terminates: a seam whose zoom is too small to read, and an area
        /// held too briefly to be read — which is what keeps the camera from
        /// pumping in and out at every stop of a road trip.
        static func make(_ request: AreaRequest) -> AreaPlan? {
            let config = request.config
            guard config.cameraAreaSplitRatio.isFinite, config.cameraAreaSplitRatio >= 1 else { return nil }
            var groups = CameraPath.group(CameraPath.stretches(request), config: config)
            while groups.count > 1 {
                // A reframe beat costs travel time, so the budget is re-read each pass.
                let draft = request.timeline(CameraPath.reframes(groups, spans: nil), nil)
                let travelS = CameraPath.travelSeconds(in: draft.entries)
                let spans = CameraPath.spansM(groups, travelS: travelS, request: request)
                if let seam = CameraPath.firstNegligibleSeam(groups, spans: spans, config: config) {
                    groups[seam] = groups[seam].merged(with: groups[seam + 1], keepingBandOf: nil)
                    groups.remove(at: seam + 1)
                    continue
                }
                let plan = AreaPlan(
                    areas: zip(groups, spans).map { group, span in
                        Area(fromM: group.fromM, toM: group.toM, localM: group.localM,
                             bounds: group.bounds, spanM: span, followsCrossing: group.followsCrossing)
                    },
                    reframes: CameraPath.reframes(groups, spans: spans)
                )
                let built = request.timeline(plan.reframes, plan)
                let startsS = CameraPath.areaStartTimesS(
                    plan: plan, reframes: built.reframes, timeline: built.entries, durationS: request.durationS
                )
                guard let brief = CameraPath.briefestAbsorbable(groups, spans: spans, startsS: startsS, request: request)
                else { return plan }
                let into = brief.into
                let (first, second) = (min(brief.index, into), max(brief.index, into))
                groups[first] = groups[first].merged(with: groups[second], keepingBandOf: groups[into])
                groups.remove(at: second)
            }
            return nil
        }
    }

    /// What `AreaPlan.make` needs from the initializer.
    struct AreaRequest {
        let route: [Point]
        let cumulativeM: [Double]
        let anchors: [(stopIndex: Int, distanceM: Double)]
        let crossings: [Crossing]
        let establishing: RecapBounds?
        let config: TrackingConfig.Export
        let durationS: Double
        /// The provisional journey clock for a given set of reframes and areas —
        /// `buildTimelineWithReframes` over the same stops, holds and crossings.
        let timeline: ([Reframe], AreaPlan?) -> (entries: [TimelineEntry], reframes: [ReframeWindow])
    }

    /// A run of route between two consecutive split points with road under it.
    struct Stretch {
        let fromM: Double
        let toM: Double
        let bounds: Bounds
        /// True when a crossing ends where this stretch begins.
        let followsCrossing: Bool
    }

    /// Consecutive stretches that share one framing.
    struct AreaGroup {
        var fromM: Double
        var toM: Double
        var localM: Double
        var bounds: Bounds
        /// The spans every member accepts: each stretch takes anything within
        /// `camera_area_split_ratio` of its own need, either way, and the group
        /// the intersection. Never empty for a group `group` built.
        var bandM: ClosedRange<Double>
        let followsCrossing: Bool

        /// The span before the pan floor: what the group's own extent asks for,
        /// held inside the band its members accept.
        func askedM(config: TrackingConfig.Export) -> Double {
            (bandM.lowerBound * bandM.upperBound).squareRoot()
        }

        /// This group and the one after it as one. The band is `keepingBandOf`'s
        /// when an area too brief to read is absorbed — a short visit is shown at
        /// the scale around it — and the hull of both for a seam too small to
        /// read, whose two bands are already within a zoom nobody sees.
        func merged(with next: AreaGroup, keepingBandOf absorber: AreaGroup?) -> AreaGroup {
            var merged = self
            merged.toM = next.toM
            merged.localM += next.localM
            merged.bounds = CameraPath.union(bounds, next.bounds)
            merged.bandM = absorber?.bandM ?? min(bandM.lowerBound, next.bandM.lowerBound)...max(
                bandM.upperBound, next.bandM.upperBound
            )
            return merged
        }
    }

    /// The span a stretch of this extent asks for alone: the old body rule on its
    /// own bounds — established (× `wide_span_padding`) ÷ `target_zoom_ratio`,
    /// floored at `camera_span_m`.
    static func areaNeedM(_ bounds: Bounds, config: TrackingConfig.Export) -> Double {
        max(
            fittingSpanM(bounds: bounds, config: config) * config.wideSpanPadding / max(config.targetZoomRatio, 1),
            config.cameraSpanM
        )
    }

    static func union(_ lhs: Bounds, _ rhs: Bounds) -> Bounds {
        Bounds(
            minLat: min(lhs.minLat, rhs.minLat), maxLat: max(lhs.maxLat, rhs.maxLat),
            minLon: min(lhs.minLon, rhs.minLon), maxLon: max(lhs.maxLon, rhs.maxLon)
        )
    }

    /// The route cut at every stop and at both ends of every crossing, keeping
    /// the pieces with road under them and some length to them.
    private static func stretches(_ request: AreaRequest) -> [Stretch] {
        guard let totalM = request.cumulativeM.last else { return [] }
        let cuts = Set([0, totalM] + request.anchors.map(\.distanceM)
            + request.crossings.flatMap { [$0.fromM, $0.toM] }).sorted()
        var built: [Stretch] = []
        var afterCrossing = false
        for (fromM, toM) in zip(cuts, cuts.dropFirst()) where toM > fromM {
            let middle = (fromM + toM) / 2
            if request.crossings.contains(where: { $0.fromM <= middle && middle <= $0.toM }) {
                afterCrossing = true
                continue
            }
            let points = points(fromM: fromM, toM: toM, request: request)
            built.append(Stretch(fromM: fromM, toM: toM, bounds: bounds(of: points), followsCrossing: afterCrossing))
            afterCrossing = false
        }
        return built
    }

    /// Greedy, in travel order, and minimal: a stretch joins the open area while
    /// some one span is still within `camera_area_split_ratio` of what **every**
    /// member asks for alone. The comparison is between each stretch's own need
    /// and not against the area's growing bounding box — which along a road trip
    /// only ever widens, and split every drive of a different length into an
    /// area of its own (measured: 16 reframes on the Iceland dump). A crossing
    /// always closes an area.
    private static func group(_ stretches: [Stretch], config: TrackingConfig.Export) -> [AreaGroup] {
        let ratio = config.cameraAreaSplitRatio
        var groups: [AreaGroup] = []
        for stretch in stretches {
            let need = areaNeedM(stretch.bounds, config: config)
            let band = need / ratio...need * ratio
            if var open = groups.last, !stretch.followsCrossing, open.bandM.overlaps(band) {
                open.toM = stretch.toM
                open.localM += stretch.toM - stretch.fromM
                open.bounds = union(open.bounds, stretch.bounds)
                open.bandM = open.bandM.clamped(to: band)
                groups[groups.count - 1] = open
                continue
            }
            groups.append(AreaGroup(
                fromM: stretch.fromM, toM: stretch.toM, localM: stretch.toM - stretch.fromM,
                bounds: stretch.bounds, bandM: band, followsCrossing: stretch.followsCrossing
            ))
        }
        return groups
    }

    /// The area held on screen for the shortest time under **two
    /// `zoom_transition_s`** that can be absorbed, and the neighbour that absorbs
    /// it: the one whose span is nearer, never across a crossing (the arc owns
    /// that seam). nil when every area is held long enough to be read.
    ///
    /// Two beats because an area is entered by one: held for less than that, the
    /// scale is on screen for less time than it took to arrive at it, and the
    /// film reads as zooming rather than as being somewhere. Derived from the
    /// zoom's own length rather than a key of its own — a first cut carried an
    /// 8 s minimum, which absorbed the drive between two towns (it has no stops
    /// of its own) and framed it at town scale.
    private static func briefestAbsorbable(
        _ groups: [AreaGroup], spans: [Double], startsS: [Double], request: AreaRequest
    ) -> (index: Int, into: Int)? {
        let heldS = groups.indices.map { index in
            (index + 1 < startsS.count ? startsS[index + 1] : request.durationS) - startsS[index]
        }
        /// An area held too briefly, and the neighbour that would absorb it.
        struct Candidate { let index: Int, into: Int, heldS: Double }
        let candidates = groups.indices.compactMap { index -> Candidate? in
            guard heldS[index] < 2 * request.config.zoomTransitionS else { return nil }
            let neighbours = [index - 1, index + 1].filter { other in
                guard groups.indices.contains(other) else { return false }
                return !groups[max(index, other)].followsCrossing
            }
            guard let into = neighbours.min(by: {
                abs(log(spans[$0] / spans[index])) < abs(log(spans[$1] / spans[index]))
            }) else { return nil }
            return Candidate(index: index, into: into, heldS: heldS[index])
        }
        return candidates.min(by: { $0.heldS < $1.heldS }).map { ($0.index, $0.into) }
    }

    /// One reframe per seam not carried by a crossing. Without spans (the
    /// provisional budget) the direction is unknown and does not matter: a beat
    /// costs the same on either side of its stop.
    private static func reframes(_ groups: [AreaGroup], spans: [Double]?) -> [Reframe] {
        (1..<max(groups.count, 1)).compactMap { index in
            guard !groups[index].followsCrossing else { return nil }
            return Reframe(atM: groups[index].fromM, zoomsIn: spans.map { $0[index] < $0[index - 1] } ?? false)
        }
    }

    /// Every area's span: its own ask, all raised by **one common factor** until
    /// no area's camera crosses ground faster than
    /// `camera_pan_window_fraction_per_s`, and none wider than its own
    /// establishing framing — `RecapDurationPlan.bodySpanM`'s floor and ceiling,
    /// over several areas at once — then held at its **context floor**, which
    /// may exceed that ceiling on purpose (ADR 2026-09-24 (e)).
    ///
    /// ⚠️ **The floor is measured on the camera's travel, not the route's.** The
    /// one-span rule charges `routeDistance / span` windows, which is exact for a
    /// drive and wrong for a town: a loop that fits inside the frame moves the
    /// dolly not at all. Charged by route length, Miyakojima's town areas were
    /// floored at 2× what they asked. `FollowCamera.travelM` is the dolly's own
    /// path over the area's geometry, so a drive still pays in full.
    private static func spansM(_ groups: [AreaGroup], travelS: Double, request: AreaRequest) -> [Double] {
        let config = request.config
        let asked = groups.map { $0.askedM(config: config) }
        let ceilings = groups.map { group in
            cappedToRegion(
                frame(for: group.bounds, config: config, padding: config.wideSpanPadding).spanM,
                establishing: request.establishing, config: config
            )
        }
        let routes = groups.map { points(fromM: $0.fromM, toM: $0.toM, request: request) }
        // Each area's own floor, never below `camera_span_m` (`CameraPathContext`).
        let floors = contextFloorsM(groups, request: request)
        func spans(_ factor: Double) -> [Double] {
            zip(zip(asked, ceilings), floors).map { max(min($0.0 * factor, $0.1), $1) }
        }
        /// The fastest any area's camera crosses its window, in windows per second,
        /// with the clock shared by screen distance (`buildTimeline`).
        func fastest(_ spans: [Double]) -> Double {
            let screen = zip(groups, spans).reduce(0.0) { $0 + $1.0.localM / $1.1 }
            guard travelS > 0, screen > 0 else { return 0 }
            return groups.indices.map { index -> Double in
                guard groups[index].localM > 0 else { return 0 }
                let cameraM = FollowCamera.travelM(
                    route: routes[index], routeBounds: groups[index].bounds, spanM: spans[index], config: config
                )
                return cameraM / groups[index].localM * screen / travelS
            }.max() ?? 0
        }
        let rate = config.cameraPanWindowFractionPerS
        guard rate > 0, fastest(spans(1)) > rate else { return spans(1) }
        // Raising every span lowers every rate, so the least factor that meets
        // the floor is found by bisection; past the last ceiling nothing moves.
        let widest = zip(asked, ceilings).map { $1 / max($0, 1) }.max() ?? 1
        guard fastest(spans(widest)) > rate else {
            var low = 1.0, high = max(widest, 1)
            for _ in 0..<40 {
                let middle = (low * high).squareRoot()
                if fastest(spans(middle)) > rate { low = middle } else { high = middle }
            }
            return spans(high)
        }
        return spans(widest)
    }

    /// Route vertices between two along-route distances, ends interpolated.
    private static func points(fromM: Double, toM: Double, request: AreaRequest) -> [Point] {
        var points = [coordinate(atDistance: fromM, route: request.route, cumulativeM: request.cumulativeM)]
        for (index, metre) in request.cumulativeM.enumerated() where metre > fromM && metre < toM {
            points.append(request.route[index])
        }
        points.append(coordinate(atDistance: toM, route: request.route, cumulativeM: request.cumulativeM))
        return points
    }

    /// The first seam between two areas whose spans differ by less than
    /// `opening_collapse_zoom_ratio` — a zoom too small to read as one, the same
    /// question the opening and the crossing arcs already answer with that key.
    /// A seam after a crossing is never merged: the arc carries it.
    private static func firstNegligibleSeam(
        _ groups: [AreaGroup], spans: [Double], config: TrackingConfig.Export
    ) -> Int? {
        (0..<(groups.count - 1)).first { index in
            guard !groups[index + 1].followsCrossing else { return false }
            let wider = max(spans[index], spans[index + 1]), tighter = min(spans[index], spans[index + 1])
            return tighter > 0 && wider < tighter * config.openingCollapseZoomRatio
        }
    }
}
