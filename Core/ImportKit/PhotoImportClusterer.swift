import Foundation

/// Turns geotagged photos into a coarse trip: stops + photo groups + a
/// time-ordered route (spec §4.7, Stage 1 of `Docs/prototype/recap_data_pipeline.py`).
///
/// Pure and deterministic — same photos + config always yield the same plan
/// (a requirement for golden-frame CI and reproducible re-exports). The app has
/// richer stop signals when *recording* (CLVisit, dwell windows); for *import*
/// the only evidence is where and when photos were taken, so a spatial+temporal
/// cluster is the reconstructed "place you spent time."
public enum PhotoImportClusterer {

    /// Builds the plan. Photos are sorted by time (ties broken by `assetId` so
    /// two photos in the same second cluster deterministically).
    public static func plan(photos: [ImportPhoto], config: ImportClusteringConfig) -> ImportedTripPlan {
        let ordered = photos.sorted { lhs, rhs in
            lhs.timestamp != rhs.timestamp ? lhs.timestamp < rhs.timestamp : lhs.assetId < rhs.assetId
        }
        guard let first = ordered.first, let last = ordered.last else { return .empty }

        let clusters = rawClusters(ordered, config: config)

        let startedAt = first.timestamp
        var stops: [ImportedStop] = []
        var routeAttached: [String] = []
        for cluster in clusters {
            if cluster.count >= config.minPhotosPerStop {
                stops.append(makeStop(cluster, tripStartedAt: startedAt))
            } else {
                routeAttached.append(contentsOf: cluster.map(\.assetId))
            }
        }

        let routePoints = ordered.map {
            ImportedRoutePoint(assetId: $0.assetId, timestamp: $0.timestamp, lat: $0.lat, lon: $0.lon)
        }
        let distance = zip(routePoints, routePoints.dropFirst()).reduce(0.0) { sum, pair in
            sum + haversineMeters(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
        }

        return ImportedTripPlan(
            stops: stops,
            routePoints: routePoints,
            legs: legs(clusters: clusters, config: config, allPoints: routePoints),
            routeAttachedAssetIds: routeAttached,
            startedAt: startedAt,
            endedAt: last.timestamp,
            approxDistanceM: distance
        )
    }

    // MARK: - Legs (one persisted segment each)

    /// Cuts the trip into inter-stop travel legs (typed-leg pass 2026-07-26).
    ///
    /// The node list alternates: a stop contributes exactly two nodes — its
    /// centroid at `arrivedAt` (where the incoming leg ends) and the same
    /// centroid at `departedAt` (where the outgoing leg starts) — while a
    /// below-threshold cluster contributes its photos as interior points, which
    /// become the route reconstructor's via-waypoints (PD-3). Photos taken
    /// *inside* a stop never enter a leg: they are the wander around a place,
    /// not the journey between places, and drawing them turns every stop into a
    /// scribble.
    ///
    /// A trip with no stop clusters (or one stop covering everything) still gets
    /// a single leg over the whole trajectory — the film must render.
    private static func legs(
        clusters: [[ImportPhoto]], config: ImportClusteringConfig, allPoints: [ImportedRoutePoint]
    ) -> [ImportedLeg] {
        var built: [ImportedLeg] = []
        var current: [ImportedRoutePoint] = []

        for cluster in clusters {
            guard cluster.count >= config.minPhotosPerStop else {
                current.append(contentsOf: cluster.map(routePoint))
                continue
            }
            let anchors = stopAnchors(cluster)
            current.append(anchors.arrival)
            if let leg = makeLeg(current) { built.append(leg) }
            current = [anchors.departure]
        }
        if let leg = makeLeg(current) { built.append(leg) }

        if built.isEmpty, let whole = makeLeg(allPoints) { built.append(whole) }
        return built
    }

    /// A stop's two leg endpoints: the centroid, timestamped at the visit's
    /// start and end. `assetId` points at the photo that evidenced each edge of
    /// the visit — the nearest real asset to that moment.
    private static func stopAnchors(
        _ cluster: [ImportPhoto]
    ) -> (arrival: ImportedRoutePoint, departure: ImportedRoutePoint) {
        let count = Double(cluster.count)
        let lat = cluster.reduce(0.0) { $0 + $1.lat } / count
        let lon = cluster.reduce(0.0) { $0 + $1.lon } / count
        return (
            ImportedRoutePoint(
                assetId: cluster.first!.assetId, timestamp: cluster.first!.timestamp, lat: lat, lon: lon
            ),
            ImportedRoutePoint(
                assetId: cluster.last!.assetId, timestamp: cluster.last!.timestamp, lat: lat, lon: lon
            )
        )
    }

    private static func makeLeg(_ points: [ImportedRoutePoint]) -> ImportedLeg? {
        guard points.count >= 2 else { return nil }
        let distanceM = zip(points, points.dropFirst()).reduce(0.0) { sum, pair in
            sum + haversineMeters(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
        }
        let elapsedS = points[points.count - 1].timestamp - points[0].timestamp
        let speed = elapsedS > 0 ? distanceM / elapsedS * 3.6 : nil
        return ImportedLeg(points: points, distanceM: distanceM, impliedSpeedKmh: speed)
    }

    private static func routePoint(_ photo: ImportPhoto) -> ImportedRoutePoint {
        ImportedRoutePoint(assetId: photo.assetId, timestamp: photo.timestamp, lat: photo.lat, lon: photo.lon)
    }

    // MARK: - Clustering

    /// Time-ordered sweep: a photo joins the current cluster while it stays
    /// within `stopRadiusM` of the running centroid AND within `stopSplitGapS`
    /// of the previous photo; otherwise a new cluster opens (§4.7 time-gap +
    /// distance). The centroid updates as photos join, so a cluster drifts to
    /// follow a walk around one place without splitting.
    private static func rawClusters(_ ordered: [ImportPhoto], config: ImportClusteringConfig) -> [[ImportPhoto]] {
        var clusters: [[ImportPhoto]] = []
        var current: [ImportPhoto] = []
        var centroidLat = 0.0
        var centroidLon = 0.0

        for photo in ordered {
            if current.isEmpty {
                current = [photo]
                centroidLat = photo.lat
                centroidLon = photo.lon
                continue
            }
            let gap = photo.timestamp - current[current.count - 1].timestamp
            let withinRadius = haversineMeters(centroidLat, centroidLon, photo.lat, photo.lon) < config.stopRadiusM
            if withinRadius && gap <= config.stopSplitGapS {
                current.append(photo)
                let count = Double(current.count)
                centroidLat += (photo.lat - centroidLat) / count
                centroidLon += (photo.lon - centroidLon) / count
            } else {
                clusters.append(current)
                current = [photo]
                centroidLat = photo.lat
                centroidLon = photo.lon
            }
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    private static func makeStop(_ cluster: [ImportPhoto], tripStartedAt: Double) -> ImportedStop {
        let count = Double(cluster.count)
        let lat = cluster.reduce(0.0) { $0 + $1.lat } / count
        let lon = cluster.reduce(0.0) { $0 + $1.lon } / count
        let arrivedAt = cluster.first!.timestamp
        let departedAt = cluster.last!.timestamp
        // Same day math as RecapComposer.dayLabel / S3 filter chips.
        let dayIndex = Int((arrivedAt - tripStartedAt) / 86_400) + 1
        return ImportedStop(
            lat: lat, lon: lon,
            arrivedAt: arrivedAt, departedAt: departedAt,
            dayIndex: dayIndex,
            photoAssetIds: cluster.map(\.assetId)
        )
    }

    /// Great-circle distance in meters (Haversine). Matches the prototype's
    /// `haversine_km`, scaled to meters for the schema's distance units.
    static func haversineMeters(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = aLat * .pi / 180
        let phi2 = bLat * .pi / 180
        let dPhi = (bLat - aLat) * .pi / 180
        let dLambda = (bLon - aLon) * .pi / 180
        let hav = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * radius * asin(min(1, sqrt(hav)))
    }
}
