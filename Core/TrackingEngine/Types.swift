import Foundation

/// Segment transport modes, matching the schema's `segment.mode` enum (§3).
public enum TransportMode: String, Equatable {
    case drive, scooter, walk, cycle, transit, unknown
}

/// What happened at a stop — persisted to `stop.kind` and rendered
/// differently by the recap (ADR 2026-07-18 stop-kind): a `walkVisit` card
/// carries the walking duration/trace, a `dwell` card doesn't. Deliberately
/// NOT the detection mechanism: a stop found via GPS silence is still a
/// dwell — the phone sat somewhere.
public enum StopKind: String, Equatable {
    case dwell
    case walkVisit = "walk_visit"
}

/// Per-trip vehicle selected at Start (§1.7). Tunes the sampling table and
/// what "automotive" motion is labeled as.
public enum VehicleType: String, CaseIterable, Equatable {
    case car, scooter, bicycle

    /// The segment mode an automotive/fast classification maps to.
    var automotiveMode: TransportMode {
        switch self {
        case .car: return .drive
        case .scooter: return .scooter
        case .bicycle: return .cycle
        }
    }
}

/// One GPS fix, decoupled from CoreLocation so the engine is replayable
/// off-device (the GPX harness feeds these).
public struct LocationSample: Equatable {
    public let ts: Double        // unix epoch seconds
    public let lat: Double
    public let lon: Double
    public let hAccM: Double?
    public let speedMps: Double? // nil → engine derives from displacement
    public let course: Double?
    public let altitudeM: Double?

    public init(
        ts: Double,
        lat: Double,
        lon: Double,
        hAccM: Double? = nil,
        speedMps: Double? = nil,
        course: Double? = nil,
        altitudeM: Double? = nil
    ) {
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.hAccM = hAccM
        self.speedMps = speedMps
        self.course = course
        self.altitudeM = altitudeM
    }
}

/// CMMotionActivity distilled to what segmentation needs (§4.1). The engine
/// only trusts activities of at least medium confidence.
public struct MotionActivity: Equatable {
    public enum Kind: Equatable {
        case automotive, cycling, walking, stationary
    }

    public let kind: Kind
    public let isAtLeastMediumConfidence: Bool

    public init(kind: Kind, isAtLeastMediumConfidence: Bool) {
        self.kind = kind
        self.isAtLeastMediumConfidence = isAtLeastMediumConfidence
    }
}

public enum Geo {
    /// Metres in one degree of latitude. Exposed rather than inlined because a
    /// second caller now needs the *inverse* — turning a ground span back into
    /// degrees, to find out whether a camera frame is even expressible as a map
    /// region (`MapKitSnapshotProvider.region`). Two copies of this number in
    /// two modules is how they drift.
    public static let metersPerDegreeLatitude = 111_320.0

    /// Equirectangular approximation — exact enough at trip scale, cheap
    /// enough to run per sample.
    ///
    /// ⚠️ **Flat-earth, and it scales longitude by the cosine of `latA` alone**,
    /// so it degrades over a long diagonal: measured 2026-09-03 on
    /// `auckland-crossing`, Taipei (25°N) → Auckland (37°S) comes out **121 km
    /// short of the great circle**, 1.4%.
    ///
    /// That is harmless for everything this powers — the camera's `cumulativeM`,
    /// the dead zone, stop anchoring — because those are *one consistent axis*
    /// and a 1.4% scale error on it is invisible. It is **not** harmless for a
    /// number a viewer reads. Use `greatCircleM` for those.
    public static func distanceM(latA: Double, lonA: Double, latB: Double, lonB: Double) -> Double {
        let dLat = (latB - latA) * metersPerDegreeLatitude
        let dLon = (lonB - lonA) * metersPerDegreeLatitude * cos(latA * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }

    /// **Haversine — for a distance that gets printed** (2026-09-03).
    ///
    /// Its own function rather than a better `distanceM`, deliberately: swapping
    /// the implementation under the camera would move every `cumulativeM`, every
    /// stop anchor and every body span on every film, to fix a defect that only
    /// exists where a figure is shown to someone. Two names, two jobs, and the
    /// doc on each says which.
    ///
    /// The caller that needed it is the Journey Card, which prints the flight's
    /// length on something shaped like a document — where being 121 km out is a
    /// claim about a journey, not a rounding (`CLAUDE.md` rule 5).
    public static func greatCircleM(latA: Double, lonA: Double, latB: Double, lonB: Double) -> Double {
        let radius = 6_371_000.0
        let phiA = latA * .pi / 180, phiB = latB * .pi / 180
        let deltaPhi = (latB - latA) * .pi / 180
        let deltaLambda = (lonB - lonA) * .pi / 180
        let haversine = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phiA) * cos(phiB) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * radius * asin(min(1, haversine.squareRoot()))
    }
}
