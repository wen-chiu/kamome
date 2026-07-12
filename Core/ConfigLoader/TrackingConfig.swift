import Foundation

/// Typed mirror of Config/TrackingConfig.json — the single home for every
/// tunable (spec §0 rule 2: no magic numbers in code).
/// Every property is non-optional: a missing key is a hard startup error.
public struct TrackingConfig: Decodable, Equatable {
    public struct Segmentation: Decodable, Equatable {
        /// A mode change must be sustained this long before a new segment opens (§4.1).
        public let modeConfirmS: Double
        /// Speed heuristic fallback thresholds (§4.1, §1.7 transit).
        public let speedDriveMinKmh: Double
        public let speedWalkMaxKmh: Double
        public let speedTransitMinKmh: Double

        enum CodingKeys: String, CodingKey {
            case modeConfirmS = "mode_confirm_s"
            case speedDriveMinKmh = "speed_drive_min_kmh"
            case speedWalkMaxKmh = "speed_walk_max_kmh"
            case speedTransitMinKmh = "speed_transit_min_kmh"
        }
    }

    public struct Dwell: Decodable, Equatable {
        /// Sliding-window stop detection (§4.2).
        public let windowS: Double
        public let radiusM: Double
        /// CLMonitor region radius while paused at a stop (§2.3).
        public let regionRadiusM: Double

        enum CodingKeys: String, CodingKey {
            case windowS = "window_s"
            case radiusM = "radius_m"
            case regionRadiusM = "region_radius_m"
        }
    }

    public struct Simplify: Decodable, Equatable {
        /// Douglas-Peucker epsilon for display polylines (§4.4).
        public let epsilonM: Double

        enum CodingKeys: String, CodingKey {
            case epsilonM = "epsilon_m"
        }
    }

    public struct SamplingPolicy: Decodable, Equatable {
        /// Symbolic name mapped to a CLLocationAccuracy constant in Phase 1.
        public let desiredAccuracy: String
        public let distanceFilterM: Double

        enum CodingKeys: String, CodingKey {
            case desiredAccuracy = "desired_accuracy"
            case distanceFilterM = "distance_filter_m"
        }
    }

    public struct Sampling: Decodable, Equatable {
        /// Adaptive sampling table (§2.3).
        public let driveFast: SamplingPolicy
        public let driveSlow: SamplingPolicy
        public let walk: SamplingPolicy

        enum CodingKeys: String, CodingKey {
            case driveFast = "drive_fast"
            case driveSlow = "drive_slow"
            case walk
        }
    }

    public struct Export: Decodable, Equatable {
        /// Recap video pipeline tunables (§4.5).
        public let targetDurationS: Double
        public let fps: Int
        public let stopHoldS: Double
        public let gifFps: Int
        public let gifWidthPx: Int

        enum CodingKeys: String, CodingKey {
            case targetDurationS = "target_duration_s"
            case fps
            case stopHoldS = "stop_hold_s"
            case gifFps = "gif_fps"
            case gifWidthPx = "gif_width_px"
        }
    }

    public let schemaVersion: Int
    public let segmentation: Segmentation
    public let dwell: Dwell
    public let simplify: Simplify
    public let sampling: Sampling
    public let export: Export

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case segmentation, dwell, simplify, sampling, export
    }
}

/// Thrown when the config file is unreadable or incomplete. The message names
/// the exact missing key so a bad config fails loudly and diagnosably.
public struct TrackingConfigError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

public enum TrackingConfigLoader {
    public static func load(contentsOf url: URL) throws -> TrackingConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TrackingConfigError(description: "TrackingConfig unreadable at \(url.path): \(error)")
        }
        return try load(from: data)
    }

    public static func load(from data: Data) throws -> TrackingConfig {
        do {
            return try JSONDecoder().decode(TrackingConfig.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw TrackingConfigError(description: "TrackingConfig missing key '\(keyPath(context, key))'")
        } catch let DecodingError.typeMismatch(_, context) {
            throw TrackingConfigError(description: "TrackingConfig wrong type at '\(keyPath(context))'")
        } catch let DecodingError.valueNotFound(_, context) {
            throw TrackingConfigError(description: "TrackingConfig null value at '\(keyPath(context))'")
        } catch {
            throw TrackingConfigError(description: "TrackingConfig is not valid JSON: \(error)")
        }
    }

    private static func keyPath(_ context: DecodingError.Context, _ missing: CodingKey? = nil) -> String {
        let path = context.codingPath + (missing.map { [$0] } ?? [])
        return path.map(\.stringValue).joined(separator: ".")
    }
}
