import Foundation

/// Segment transport modes, matching the schema's `segment.mode` enum (§3).
public enum TransportMode: String, Equatable {
    case drive, scooter, walk, cycle, transit, unknown
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

enum Geo {
    /// Equirectangular approximation — exact enough at trip scale, cheap
    /// enough to run per sample.
    static func distanceM(latA: Double, lonA: Double, latB: Double, lonB: Double) -> Double {
        let mPerDegLat = 111_320.0
        let dLat = (latB - latA) * mPerDegLat
        let dLon = (lonB - lonA) * mPerDegLat * cos(latA * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}
