import XCTest

@testable import KamomeImportKit

final class PhotoImportClustererTests: XCTestCase {
    // 2 km join radius, no time-gap split unless > 1 h, a stop needs ≥ 2 photos.
    private let config = ImportClusteringConfig(stopRadiusM: 2_000, stopSplitGapS: 3_600, minPhotosPerStop: 2)

    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// A → (lone route photo) → B (day 1) → C (day 2). Clusters far apart in
    /// space; within-stop jitter < radius.
    private func icelandLikeTrip() -> [ImportPhoto] {
        [
            // Stop A — 3 photos, ~50 m apart
            photo("a1", 0, 63.4040, -19.0410),
            photo("a2", 60, 63.4044, -19.0405),
            photo("a3", 120, 63.4041, -19.0412),
            // lone photo mid-drive — its own 1-photo cluster → route-attached
            photo("lone", 3_600, 63.4500, -18.5000),
            // Stop B — 5 photos next
            photo("b1", 7_200, 63.5300, -19.5500),
            photo("b2", 7_260, 63.5305, -19.5495),
            photo("b3", 7_320, 63.5302, -19.5502),
            photo("b4", 7_380, 63.5299, -19.5498),
            photo("b5", 7_440, 63.5301, -19.5501),
            // Stop C — 2 photos, day 2 (ts > 86400)
            photo("c1", 90_000, 64.0500, -16.1800),
            photo("c2", 90_060, 64.0505, -16.1795)
        ]
    }

    func testClustersIntoStopsRouteAndAttachments() {
        let plan = PhotoImportClusterer.plan(photos: icelandLikeTrip(), config: config)

        XCTAssertEqual(plan.stops.count, 3, "A, B, C are stops; the lone photo is not")
        XCTAssertEqual(plan.stops.map(\.photoAssetIds.count), [3, 5, 2])
        XCTAssertEqual(plan.routeAttachedAssetIds, ["lone"])
        XCTAssertEqual(plan.routePoints.count, 11, "route = every photo in time order")
        XCTAssertTrue(plan.isRenderable)
        XCTAssertEqual(plan.startedAt, 0)
        XCTAssertEqual(plan.endedAt, 90_060)
        XCTAssertGreaterThan(plan.approxDistanceM, 0)
    }

    func testStopsAreTimeOrderedWithDayIndexAndSpan() {
        let plan = PhotoImportClusterer.plan(photos: icelandLikeTrip(), config: config)

        XCTAssertEqual(plan.stops.map(\.arrivedAt), [0, 7_200, 90_000])
        XCTAssertEqual(plan.stops.map(\.departedAt), [120, 7_440, 90_060])
        XCTAssertEqual(plan.stops.map(\.dayIndex), [1, 1, 2])

        // Stop A centroid = average of its three photos.
        let stopA = plan.stops[0]
        XCTAssertEqual(stopA.lat, (63.4040 + 63.4044 + 63.4041) / 3, accuracy: 1e-9)
        XCTAssertEqual(stopA.lon, (-19.0410 - 19.0405 - 19.0412) / 3, accuracy: 1e-9)
    }

    /// Same place, but a gap larger than `stopSplitGapS` = a second visit.
    func testTimeGapSplitsARevisitedPlace() {
        let photos = [
            photo("m1", 0, 65.6260, -16.9160),
            photo("m2", 60, 65.6262, -16.9158),
            photo("m3", 100_000, 65.6261, -16.9161),   // returned much later
            photo("m4", 100_060, 65.6263, -16.9159)
        ]
        let plan = PhotoImportClusterer.plan(photos: photos, config: config)
        XCTAssertEqual(plan.stops.count, 2, "a >1 h gap at the same place = two visits")
        XCTAssertEqual(plan.stops.map(\.photoAssetIds.count), [2, 2])
    }

    func testUnsortedInputIsOrderedDeterministically() {
        let shuffled = icelandLikeTrip().reversed()
        let planA = PhotoImportClusterer.plan(photos: Array(shuffled), config: config)
        let planB = PhotoImportClusterer.plan(photos: icelandLikeTrip(), config: config)
        XCTAssertEqual(planA, planB, "clustering is order-independent and deterministic")
    }

    func testEmptyAndSinglePhotoAreNotRenderable() {
        XCTAssertEqual(PhotoImportClusterer.plan(photos: [], config: config), .empty)

        let single = PhotoImportClusterer.plan(photos: [photo("x", 0, 10, 10)], config: config)
        XCTAssertFalse(single.isRenderable, "one photo cannot make a trip")
        XCTAssertEqual(single.stops.count, 0, "one photo is below minPhotosPerStop")
        XCTAssertEqual(single.routeAttachedAssetIds, ["x"])
        XCTAssertTrue(single.legs.isEmpty, "one point cannot make a leg")
    }

    // MARK: - Legs (typed-leg pass 2026-07-26)

    /// A ─(lone)─ B ─ C gives two travel legs: within-stop photos are the wander
    /// around a place, not the journey between places, so they never enter a leg.
    func testLegsSpanStopToStopCarryingRouteAttachedPhotosBetween() {
        let plan = PhotoImportClusterer.plan(photos: icelandLikeTrip(), config: config)

        XCTAssertEqual(plan.legs.count, 2, "A→B and B→C; nothing before A or after C")
        XCTAssertEqual(plan.legs[0].points.map(\.assetId), ["a3", "lone", "b1"],
                       "the lone photo rides between the two stop anchors as a via-waypoint")
        XCTAssertEqual(plan.legs[1].points.map(\.assetId), ["b5", "c1"])
    }

    /// Legs are cut at stop *centroids*, so leg k ends exactly where leg k+1
    /// begins and the concatenated route has no gap at a stop.
    func testLegEndpointsAreStopCentroidsSoTheRouteStaysContinuous() {
        let plan = PhotoImportClusterer.plan(photos: icelandLikeTrip(), config: config)
        let stopB = plan.stops[1]

        let arrival = plan.legs[0].points.last!
        let departure = plan.legs[1].points.first!
        XCTAssertEqual(arrival.lat, stopB.lat, accuracy: 1e-12)
        XCTAssertEqual(arrival.lon, stopB.lon, accuracy: 1e-12)
        XCTAssertEqual(departure.lat, arrival.lat, accuracy: 1e-12, "no gap across the stop")
        XCTAssertEqual(departure.lon, arrival.lon, accuracy: 1e-12)

        // The anchors carry the visit's own edges in time.
        XCTAssertEqual(arrival.timestamp, stopB.arrivedAt)
        XCTAssertEqual(departure.timestamp, stopB.departedAt)
    }

    /// The classifier input (PD-8) — the clusterer measures pace, it never
    /// decides transport mode.
    func testLegsCarryDistanceAndImpliedPace() throws {
        // ~500 m apart, 10 min elapsed → ~3 km/h: walking pace.
        let strollPhotos = [
            photo("s1", 0, 63.4040, -19.0410),
            photo("s2", 60, 63.4044, -19.0405),
            photo("s3", 600, 63.4080, -19.0400),
            photo("s4", 660, 63.4084, -19.0395)
        ]
        let plan = PhotoImportClusterer.plan(photos: strollPhotos, config: config)
        XCTAssertEqual(plan.legs.count, 1)
        let leg = try XCTUnwrap(plan.legs.first)
        XCTAssertGreaterThan(leg.distanceM, 0)
        XCTAssertLessThan(try XCTUnwrap(leg.impliedSpeedKmh), 6, "a stroll reads as walking pace")
    }

    /// No stop clusters at all (every cluster below threshold) still renders:
    /// one leg over the whole trajectory rather than a film with no route.
    func testTripWithoutStopsStillProducesOneLeg() {
        let scattered = [
            photo("p1", 0, 63.40, -19.04),
            photo("p2", 3_600, 63.60, -19.40),
            photo("p3", 7_200, 63.90, -18.90)
        ]
        let plan = PhotoImportClusterer.plan(photos: scattered, config: config)
        XCTAssertTrue(plan.stops.isEmpty)
        XCTAssertEqual(plan.legs.count, 1)
        XCTAssertEqual(plan.legs[0].points.map(\.assetId), ["p1", "p2", "p3"])
        XCTAssertTrue(plan.isRenderable)
    }

    /// One stop swallowing every photo leaves no inter-stop travel — the
    /// fallback leg keeps the trip renderable instead of yielding zero segments.
    func testSingleStopTripFallsBackToAWholeTrajectoryLeg() {
        let oneplace = [
            photo("q1", 0, 63.4040, -19.0410),
            photo("q2", 60, 63.4044, -19.0405),
            photo("q3", 120, 63.4041, -19.0412)
        ]
        let plan = PhotoImportClusterer.plan(photos: oneplace, config: config)
        XCTAssertEqual(plan.stops.count, 1)
        XCTAssertEqual(plan.legs.count, 1, "fallback: the whole trajectory")
        XCTAssertEqual(plan.legs[0].points.count, 3)
        XCTAssertTrue(plan.isRenderable)
    }
}

final class PhotoDeckSelectorTests: XCTestCase {
    private let ids = (0..<20).map { "p\($0)" }

    func testCapsAtMaxAndKeepsEndpoints() {
        let deck = PhotoDeckSelector.evenlySpread(ids, min: 3, max: 8)
        XCTAssertEqual(deck.count, 8)
        XCTAssertEqual(deck.first, "p0")
        XCTAssertEqual(deck.last, "p19")
        XCTAssertEqual(deck, deck.sorted { ids.firstIndex(of: $0)! < ids.firstIndex(of: $1)! },
                       "order preserved")
        XCTAssertEqual(Set(deck).count, deck.count, "no repeats")
    }

    func testReturnsAllWhenFewerThanWanted() {
        XCTAssertEqual(PhotoDeckSelector.evenlySpread(["a", "b"], min: 3, max: 8), ["a", "b"])
        XCTAssertEqual(PhotoDeckSelector.evenlySpread(Array(ids.prefix(5)), min: 3, max: 8),
                       Array(ids.prefix(5)))
    }

    func testDeterministicAndEmpty() {
        XCTAssertEqual(PhotoDeckSelector.evenlySpread([], min: 3, max: 8), [])
        XCTAssertEqual(PhotoDeckSelector.evenlySpread(ids, min: 3, max: 8),
                       PhotoDeckSelector.evenlySpread(ids, min: 3, max: 8))
    }
}
