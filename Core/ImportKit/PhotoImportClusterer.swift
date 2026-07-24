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
            routeAttachedAssetIds: routeAttached,
            startedAt: startedAt,
            endedAt: last.timestamp,
            approxDistanceM: distance
        )
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
