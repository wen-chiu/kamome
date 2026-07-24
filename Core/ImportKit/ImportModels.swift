import Foundation

/// One geotagged photo, reduced to the fields import needs. `assetId` is the
/// opaque PhotoKit local identifier — ImportKit never touches PhotoKit, so this
/// module stays pure and deterministically testable (the PhotoKit → ImportPhoto
/// adapter lives in the app, spec §4.7). Image bytes are never carried here.
public struct ImportPhoto: Equatable, Sendable {
    public let assetId: String
    /// EXIF creation time, unix epoch seconds.
    public let timestamp: Double
    public let lat: Double
    public let lon: Double

    public init(assetId: String, timestamp: Double, lat: Double, lon: Double) {
        self.assetId = assetId
        self.timestamp = timestamp
        self.lat = lat
        self.lon = lon
    }
}

/// Tunables for photo → stops/route clustering (spec §4.7 "time-gap + distance
/// heuristics"). No magic numbers: the app builds this from the `import` block
/// of `TrackingConfig.json` (§0 rule 2). Defaults mirror the validated
/// prototype (`Docs/prototype/recap_data_pipeline.py`), to be tuned against the
/// three real dogfood trips.
public struct ImportClusteringConfig: Equatable, Sendable {
    /// A photo joins the running cluster while within this distance of its
    /// centroid; beyond it, a new cluster (place) opens. Prototype: 4 km.
    public let stopRadiusM: Double
    /// A time gap larger than this between consecutive photos also opens a new
    /// cluster even inside the radius — you left and came back (a new visit).
    public let stopSplitGapS: Double
    /// A cluster becomes a `stop` only with at least this many photos; smaller
    /// clusters stay route-attached (real photos, just not a place you dwelt).
    public let minPhotosPerStop: Int

    public init(stopRadiusM: Double, stopSplitGapS: Double, minPhotosPerStop: Int) {
        self.stopRadiusM = stopRadiusM
        self.stopSplitGapS = stopSplitGapS
        self.minPhotosPerStop = minPhotosPerStop
    }
}

/// A reconstructed place: a spatial+temporal cluster of photos = somewhere the
/// traveler spent time (spec §4.2/§4.7). Photo count is the significance proxy
/// the prototype validated (a big shoot = a place that mattered).
public struct ImportedStop: Equatable, Sendable {
    /// Cluster centroid.
    public let lat: Double
    public let lon: Double
    /// First / last photo time in the cluster.
    public let arrivedAt: Double
    public let departedAt: Double
    /// 1-based day from trip start — same math as `RecapComposer.dayLabel`.
    public let dayIndex: Int
    /// Every photo in the cluster, in time order (the full group; the render
    /// deck picks a 3–8 subset via `PhotoDeckSelector`).
    public let photoAssetIds: [String]

    public init(lat: Double, lon: Double, arrivedAt: Double, departedAt: Double,
                dayIndex: Int, photoAssetIds: [String]) {
        self.lat = lat
        self.lon = lon
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
        self.dayIndex = dayIndex
        self.photoAssetIds = photoAssetIds
    }
}

/// One coarse route point (a photo position in time order) — the real
/// trajectory before OSRM snaps it to roads (§4.4). Straight lines between
/// these are honest only until snapped; low-confidence legs render inferred.
public struct ImportedRoutePoint: Equatable, Sendable {
    public let assetId: String
    public let timestamp: Double
    public let lat: Double
    public let lon: Double

    public init(assetId: String, timestamp: Double, lat: Double, lon: Double) {
        self.assetId = assetId
        self.timestamp = timestamp
        self.lat = lat
        self.lon = lon
    }
}

/// The pure result of clustering — everything the persistence writer needs to
/// materialize an `imported_photos` trip (schema v2, §3) that then flows through
/// the existing Trip Detail / RecapComposer / ExportEngine unchanged.
public struct ImportedTripPlan: Equatable, Sendable {
    public let stops: [ImportedStop]
    /// All photos in time order (pre-OSRM), one drive segment's trackpoints.
    public let routePoints: [ImportedRoutePoint]
    /// Photos whose cluster fell below `minPhotosPerStop` — route-attached
    /// (`stop_id = NULL`), still real photos.
    public let routeAttachedAssetIds: [String]
    public let startedAt: Double
    public let endedAt: Double
    /// Great-circle distance summed along `routePoints` (pre-snap estimate).
    public let approxDistanceM: Double

    public init(stops: [ImportedStop], routePoints: [ImportedRoutePoint],
                routeAttachedAssetIds: [String], startedAt: Double,
                endedAt: Double, approxDistanceM: Double) {
        self.stops = stops
        self.routePoints = routePoints
        self.routeAttachedAssetIds = routeAttachedAssetIds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.approxDistanceM = approxDistanceM
    }

    /// The phantom-trip guard for import: a recap needs ≥ 2 route points
    /// (RecapComposer returns nil otherwise). An empty/one-photo import is not
    /// a trip.
    public var isRenderable: Bool { routePoints.count >= 2 }

    public static let empty = ImportedTripPlan(
        stops: [], routePoints: [], routeAttachedAssetIds: [],
        startedAt: 0, endedAt: 0, approxDistanceM: 0
    )
}
