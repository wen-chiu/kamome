import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **An area is never framed deeper than the place it sits in allows**
/// (ADR 2026-09-24 (e)).
///
/// ## Why
///
/// Camera areas (ADR 2026-09-24) frame a town at town scale, floored only at
/// `camera_span_m`. On Miyakojima that is 1.9 km, and Chiu: *「太細部的行程會不知道
/// 自己在哪裡」*. At that scale the frame holds village labels and a stretch of
/// coast, and nothing a viewer recognises.
///
/// The two framings Chiu judged are two *depths* below the island they sit on:
/// 19 km is 1.7× inside it (too wide), 1.9 km is 17× inside it (too tight).
/// No single metre floor serves an island town and a road-trip town both, so the
/// floor is relative: `context_depth` below **the place the area sits in**.
///
/// ## Finding "the place": the trip's own scale ladder
///
/// Single-linkage over the film's stops (a minimum spanning tree), cut into
/// levels wherever a link is more than `context_level_break_ratio` times the
/// longest link below it. Measured on the committed fixtures, the levels are
/// the ones a person would name: on `miyakojima-round-trip` town → 32.5 km
/// island → Taiwan, on `auckland-crossing` town → 34 km region → country
/// (`Tools/stop-scale-ladder.py`). An area's parent is the smallest level that
/// holds all of its stops **and at least one more**. When none does, the parent
/// is the whole trip.
///
/// ## Why it cannot move a one-area film
///
/// The parent of a one-area film is the whole trip, so its floor is
/// `fitting ÷ context_depth`. The area's own ask is `fitting × wide_span_padding
/// ÷ target_zoom_ratio` (0.6 × fitting as shipped), which is always wider for
/// any depth above 1.7. A one-area film also never reaches `spansM` at all:
/// `AreaPlan.make` returns nil. Both hold, so the one-span path is untouched.
///
/// ## Why the cap
///
/// On a road trip the level above a town is the whole route: a line, not a
/// place. Divided by 5, Iceland's would frame Reykjavík at about 175 km.
/// `context_span_max_m` stops the floor at city scale.
extension CameraPath {
    /// The trip's places, nested: stop membership at every level, finest first.
    struct ContextLadder {
        /// One link of the spanning tree over the stops.
        struct Link {
            let from: Int
            let to: Int
            let lengthM: Double
        }

        let points: [Point]
        /// For every level, each stop's place id. The last level is the whole
        /// trip, so it is never empty.
        let levels: [[Int]]

        init(points: [Point], config: TrackingConfig.Export) {
            self.points = points
            let links = Self.spanningTree(points).sorted { $0.lengthM < $1.lengthM }
            var breaksM: [Double] = []
            var longestM = 0.0
            for link in links {
                // Links shorter than the tightest frame are noise within one
                // place — two photos of one car park — so they never set the scale.
                let belowM = max(longestM, config.cameraSpanM)
                if link.lengthM > config.cameraContext.contextLevelBreakRatio * belowM {
                    breaksM.append(link.lengthM)
                }
                longestM = link.lengthM
            }
            levels = (breaksM + [.infinity]).map { Self.places(count: points.count, links: links, shorterThanM: $0) }
        }

        /// The smallest place that holds every stop in `members` and at least one
        /// more; the whole trip when no level does.
        func parent(of members: Set<Int>) -> [Point] {
            guard let first = members.first else { return points }
            for level in levels {
                let place = level[first]
                guard members.allSatisfy({ level[$0] == place }) else { continue }
                let held = level.indices.filter { level[$0] == place }
                if held.count > members.count { return held.map { points[$0] } }
            }
            return points
        }

        /// Prim's algorithm: O(n²), deterministic, and small — a film presents
        /// tens of stops.
        static func spanningTree(_ points: [Point]) -> [Link] {
            guard points.count > 1 else { return [] }
            func lengthM(_ lhs: Int, _ rhs: Int) -> Double {
                Geo.distanceM(latA: points[lhs].lat, lonA: points[lhs].lon, latB: points[rhs].lat, lonB: points[rhs].lon)
            }
            var inTree = Array(repeating: false, count: points.count)
            inTree[0] = true
            var nearestM = points.indices.map { lengthM(0, $0) }
            var nearestFrom = Array(repeating: 0, count: points.count)
            var links: [Link] = []
            for _ in 1..<points.count {
                guard let next = points.indices.filter({ !inTree[$0] }).min(by: { nearestM[$0] < nearestM[$1] })
                else { break }
                inTree[next] = true
                links.append(Link(from: nearestFrom[next], to: next, lengthM: nearestM[next]))
                for other in points.indices where !inTree[other] {
                    let length = lengthM(next, other)
                    if length < nearestM[other] {
                        nearestM[other] = length
                        nearestFrom[other] = next
                    }
                }
            }
            return links
        }

        /// Each stop's place id when only links shorter than `limitM` join places.
        static func places(count: Int, links: [Link], shorterThanM limitM: Double) -> [Int] {
            var root = Array(0..<count)
            func find(_ index: Int) -> Int {
                var index = index
                while root[index] != index { index = root[index] }
                return index
            }
            for link in links where link.lengthM < limitM {
                let from = find(link.from), to = find(link.to)
                root[from] = to
            }
            return (0..<count).map { find($0) }
        }
    }

    /// Every area's context floor: the fitting span of the place it sits in ÷
    /// `context_depth`, no tighter than `camera_span_m` and no wider than
    /// `context_span_max_m` — or its **next-town floor** when that is wider.
    /// An area with no stop of its own gets `camera_span_m`.
    static func contextFloorsM(_ groups: [AreaGroup], request: AreaRequest) -> [Double] {
        contextOnlyFloorsM(groups, request: request)
    }

    /// **One journey scale per trip, from its own density of towns** (ADR file
    /// 2026-09-28, Chiu 2026-09-29). nil for an area that keeps its own framing;
    /// otherwise the span it is shown at.
    ///
    /// **You know where you are when you can see the next town**
    /// (「旅程地點行進長度密度不同我們要顯示的畫面大小就要有所變化」). For every stop,
    /// the frame centred on it that holds the nearest stop of another town;
    /// the journey scale is the median over the trip's stops. So a road trip
    /// between towns 50 km apart is framed wide throughout, and does not zoom
    /// in and out as the towns thin and thicken; a trip that is all one town
    /// has no scale, and nothing here changes it. No distance is tuned to any trip.
    ///
    /// An area keeps its own, tighter framing only when it **earns the zoom**:
    /// its stops are all one town, it fits inside the journey's frame, and its
    /// route crosses at
    /// least 2 × `zoom_transition_s` × the travel rate windows of the frame that
    /// just holds it — days driven around a town. An airport and a mall on the
    /// way out of a city, three lakeside stops, or the road in and out of a
    /// national park past two other towns are passed through and shown at the
    /// journey's scale (「除非是使用者有市區行程…我們可以拉近得到更好的路線軌跡」).
    static func journeySpansM(_ groups: [AreaGroup], request: AreaRequest) -> [Double?] {
        let anchors = request.anchors
        let points = anchors.map {
            coordinate(atDistance: $0.distanceM, route: request.route, cumulativeM: request.cumulativeM)
        }
        let place = placeIds(anchors: anchors, points: points, request: request)
        let frames = nextTownFramesM(request, points: points, place: place).filter { $0 > 0 }.sorted()
        guard !frames.isEmpty else { return groups.map { _ in nil } }
        let median = frames.count % 2 == 1
            ? frames[frames.count / 2] : (frames[frames.count / 2 - 1] * frames[frames.count / 2]).squareRoot()
        let config = request.config
        let scaleM = cappedToRegion(median, establishing: request.establishing, config: config)
        let rate = config.travelPacing.isEnabled ? config.travelPacing.windowsPerS : config.cameraPanWindowFractionPerS
        let earnedWindows = 2 * config.zoomTransitionS * rate
        return groups.map { group in
            let fitM = fittingSpanM(bounds: group.bounds, config: config)
            let towns = Set(anchors.indices.filter {
                anchors[$0].distanceM >= group.fromM && anchors[$0].distanceM <= group.toM
            }.compactMap { place[$0] })
            let earned = towns.count <= 1 && fitM < scaleM && group.localM / max(fitM, 1) >= earnedWindows
            return earned ? nil : scaleM
        }
    }

    /// For each stop (anchor), the frame centred on it that holds the nearest
    /// stops of the **two** nearest other places — one reference says how far,
    /// two say where — or 0 when there are not two. Never across a crossing:
    /// the town past a flight belongs to another journey.
    static func nextTownFramesM(_ request: AreaRequest, points: [Point], place: [Int?]) -> [Double] {
        let anchors = request.anchors
        guard anchors.count > 2 else { return anchors.map { _ in 0 } }
        return anchors.indices.map { stop in
            guard let own = place[stop] else { return 0 }
            var nearestOf: [Int: (index: Int, metres: Double)] = [:]
            for other in anchors.indices {
                guard let otherPlace = place[other], otherPlace != own else { continue }
                let low = min(anchors[stop].distanceM, anchors[other].distanceM)
                let high = max(anchors[stop].distanceM, anchors[other].distanceM)
                guard !request.crossings.contains(where: { $0.fromM >= low && $0.toM <= high }) else { continue }
                let metres = Geo.distanceM(
                    latA: points[stop].lat, lonA: points[stop].lon, latB: points[other].lat, lonB: points[other].lon
                )
                if metres < nearestOf[otherPlace]?.metres ?? .infinity { nearestOf[otherPlace] = (other, metres) }
            }
            let two = nearestOf.values.sorted { $0.metres < $1.metres }.prefix(2)
            guard two.count == 2 else { return 0 }
            // The frame centred on the stop that holds both: each and its mirror.
            let held = two.flatMap { other -> [Point] in
                let point = points[other.index]
                return [point, Point(lat: 2 * points[stop].lat - point.lat, lon: 2 * points[stop].lon - point.lon)]
            }
            return fittingSpanM(bounds: bounds(of: held), config: request.config)
        }
    }

    /// Each anchor's place, or nil when it cannot be a reference. A place is a
    /// named town (`locality`) joined with every stop within `camera_span_m` of
    /// it — geocoded towns are noisy, and stops that close are one spot on any
    /// frame. A viewer places themselves by named towns, so an unnamed stop is no
    /// reference, and a trip with no names has none.
    private static func placeIds(
        anchors: [(stopIndex: Int, distanceM: Double)], points: [Point], request: AreaRequest
    ) -> [Int?] {
        let town = anchors.map { anchor -> String? in
            guard anchor.stopIndex < request.places.count, let name = request.places[anchor.stopIndex],
                  !name.isEmpty else { return nil }
            return name
        }
        // No names at all: no references. Clusters of unnamed stops were tried
        // and made every photo spot on an island a "town" (the round trip widened
        // from 6.5 to 27 km) — so an unnamed trip is framed exactly as before.
        guard town.contains(where: { $0 != nil }) else { return anchors.map { _ in nil } }
        var root = Array(anchors.indices)
        func find(_ index: Int) -> Int {
            var index = index
            while root[index] != index { index = root[index] }
            return index
        }
        var firstOfTown: [String: Int] = [:]
        for index in anchors.indices {
            if let name = town[index] {
                if let seen = firstOfTown[name] { root[find(index)] = find(seen) } else { firstOfTown[name] = index }
            }
            for other in 0..<index where Geo.distanceM(
                latA: points[index].lat, lonA: points[index].lon, latB: points[other].lat, lonB: points[other].lon
            ) <= request.config.cameraSpanM {
                root[find(index)] = find(other)
            }
        }
        return anchors.indices.map { index in
            let id = find(index)
            return anchors.indices.contains { find($0) == id && town[$0] != nil } ? id : nil
        }
    }

    private static func contextOnlyFloorsM(_ groups: [AreaGroup], request: AreaRequest) -> [Double] {
        let config = request.config, context = config.cameraContext
        guard context.isEnabled, request.anchors.count > 1 else { return groups.map { _ in config.cameraSpanM } }
        let points = request.anchors.map {
            coordinate(atDistance: $0.distanceM, route: request.route, cumulativeM: request.cumulativeM)
        }
        let ladder = ContextLadder(points: points, config: config)
        let ceilingM = max(context.contextSpanMaxM, config.cameraSpanM)
        return groups.map { group in
            // Cuts are made at anchor distances, so an area's ends are exactly
            // the anchors that bound it — a stop at a seam belongs to both sides.
            let members = Set(request.anchors.indices.filter {
                request.anchors[$0].distanceM >= group.fromM && request.anchors[$0].distanceM <= group.toM
            })
            guard !members.isEmpty else { return config.cameraSpanM }
            let placeM = fittingSpanM(bounds: bounds(of: ladder.parent(of: members)), config: config)
            let floorM = min(max(placeM / context.contextDepth, config.cameraSpanM), ceilingM)
            return cappedToRegion(floorM, establishing: request.establishing, config: config)
        }
    }
}
