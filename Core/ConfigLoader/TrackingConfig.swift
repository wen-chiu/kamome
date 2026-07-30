import Foundation

/// Typed mirror of Config/TrackingConfig.json — the single home for every
/// tunable (spec §0 rule 2: no magic numbers in code).
/// Every property is non-optional: a missing key is a hard startup error.
public struct TrackingConfig: Decodable, Equatable {
    public struct Filter: Decodable, Equatable {
        /// Samples with horizontal accuracy worse than this are discarded.
        public let maxHAccM: Double
        /// Samples worse than this draw the route but are excluded as speed
        /// evidence (2026-07-18: an h_acc 43–49 m glitch tagged 137 m/s → 495 km/h).
        public let speedMaxHAccM: Double

        enum CodingKeys: String, CodingKey {
            case maxHAccM = "max_h_acc_m"
            case speedMaxHAccM = "speed_max_h_acc_m"
        }
    }

    public struct Segmentation: Decodable, Equatable {
        /// A mode change must be sustained this long before a new segment opens (§4.1).
        public let modeConfirmS: Double
        /// Speeds are averaged over this window before classification.
        public let speedSmoothingWindowS: Double
        /// Below this the classifier reports "no evidence" (GPS jitter at rest);
        /// dwell detection owns stationariness, not segmentation.
        public let speedStationaryMaxKmh: Double
        /// Speed heuristic fallback thresholds (§4.1, §1.7 transit).
        public let speedWalkMaxKmh: Double
        public let speedDriveMinKmh: Double
        public let speedTransitMinKmh: Double

        enum CodingKeys: String, CodingKey {
            case modeConfirmS = "mode_confirm_s"
            case speedSmoothingWindowS = "speed_smoothing_window_s"
            case speedStationaryMaxKmh = "speed_stationary_max_kmh"
            case speedWalkMaxKmh = "speed_walk_max_kmh"
            case speedDriveMinKmh = "speed_drive_min_kmh"
            case speedTransitMinKmh = "speed_transit_min_kmh"
        }
    }

    public struct Dwell: Decodable, Equatable {
        /// Sliding-window stop detection (§4.2).
        public let windowS: Double
        public let radiusM: Double
        /// CLMonitor region radius while paused at a stop (§2.3).
        public let regionRadiusM: Double
        /// Trip-end stop derivation (ADR 2026-07-18): a sample-silence gap this
        /// long with displacement ≤ radius_m is a stop the live detector can't see.
        public let gapMinS: Double
        /// A walk segment bracketed by vehicle segments is a stop ("park and walk
        /// around") when it lasts ≥ visit_min_s and ends within
        /// visit_return_radius_m of where it began — loop closure, not wander extent.
        public let visitMinS: Double
        public let visitReturnRadiusM: Double

        enum CodingKeys: String, CodingKey {
            case windowS = "window_s"
            case radiusM = "radius_m"
            case regionRadiusM = "region_radius_m"
            case gapMinS = "gap_min_s"
            case visitMinS = "visit_min_s"
            case visitReturnRadiusM = "visit_return_radius_m"
        }
    }

    public struct Simplify: Decodable, Equatable {
        /// Douglas-Peucker epsilon for display polylines (§4.4).
        public let epsilonM: Double

        enum CodingKeys: String, CodingKey {
            case epsilonM = "epsilon_m"
        }
    }

    // `Matching` lives in TrackingConfigMatching.swift — the §4.4 block grew
    // its own tunables and both files stay inside the size budget.

    public struct Photos: Decodable, Equatable {
        /// GPS-tagged photos attach to the nearest stop within this radius (§4.3).
        public let matchRadiusM: Double

        enum CodingKeys: String, CodingKey {
            case matchRadiusM = "match_radius_m"
        }
    }

    public struct Import: Decodable, Equatable {
        /// Photo-EXIF clustering tunables (§4.7). Defaults mirror the validated
        /// prototype (`Docs/prototype/recap_data_pipeline.py`); tune against the
        /// three real dogfood trips (the Replay MVP gate).
        /// A photo joins a cluster while within this distance of its centroid.
        public let stopRadiusM: Double
        /// A larger time gap between consecutive photos opens a new cluster
        /// (a revisit) even inside the radius.
        public let stopSplitGapS: Double
        /// A cluster becomes a stop only with at least this many photos.
        public let minPhotosPerStop: Int
        /// Recap photo-deck size bounds (basic MVP presentation; §5).
        public let deckMinPhotos: Int
        public let deckMaxPhotos: Int
        /// How many days back the S1 import date-range picker defaults to
        /// (UI default only — the user adjusts it; kept here so it isn't a
        /// magic number, §0 rule 2).
        public let defaultRangeDays: Int

        enum CodingKeys: String, CodingKey {
            case stopRadiusM = "stop_radius_m"
            case stopSplitGapS = "stop_split_gap_s"
            case minPhotosPerStop = "min_photos_per_stop"
            case deckMinPhotos = "deck_min_photos"
            case deckMaxPhotos = "deck_max_photos"
            case defaultRangeDays = "default_range_days"
        }
    }

    public struct Geocode: Decodable, Equatable {
        /// CLGeocoder is throttled and cached (§4.2).
        public let minIntervalS: Double
        /// Coordinates round to this grid for cache lookups (~110 m at 0.001°).
        public let cachePrecisionDeg: Double

        enum CodingKeys: String, CodingKey {
            case minIntervalS = "min_interval_s"
            case cachePrecisionDeg = "cache_precision_deg"
        }
    }

    public struct Trip: Decodable, Equatable {
        /// A finished recording below either minimum is discarded as a phantom
        /// trip (accidental start/stop) instead of saved — a zero-length trip
        /// is a degenerate input for the §4.5 recap camera path.
        public let minDurationS: Double
        public let minDistanceM: Double

        public init(minDurationS: Double, minDistanceM: Double) {
            self.minDurationS = minDurationS
            self.minDistanceM = minDistanceM
        }

        enum CodingKeys: String, CodingKey {
            case minDurationS = "min_duration_s"
            case minDistanceM = "min_distance_m"
        }
    }

    public struct SamplingPolicy: Decodable, Equatable {
        /// Symbolic name mapped to a CLLocationAccuracy constant by the app.
        public let desiredAccuracy: String
        public let distanceFilterM: Double

        enum CodingKeys: String, CodingKey {
            case desiredAccuracy = "desired_accuracy"
            case distanceFilterM = "distance_filter_m"
        }
    }

    public struct VehiclePreset: Decodable, Equatable {
        /// At or above this speed the "fast" policy applies, else "slow" (§2.3).
        public let fastMinKmh: Double
        public let fast: SamplingPolicy
        public let slow: SamplingPolicy

        enum CodingKeys: String, CodingKey {
            case fastMinKmh = "fast_min_kmh"
            case fast, slow
        }
    }

    public struct Sampling: Decodable, Equatable {
        public struct Vehicles: Decodable, Equatable {
            /// Per-vehicle presets (§1.7): scooter/bicycle = lower speeds,
            /// tighter filters, more stops.
            public let car: VehiclePreset
            public let scooter: VehiclePreset
            public let bicycle: VehiclePreset
        }

        /// Adaptive sampling table (§2.3).
        public let walk: SamplingPolicy
        public let vehicles: Vehicles
        /// Watchdog for silent background-session death (2026-07-19 drive: iOS
        /// suspended the app ~10 s after a region-exit wake, losing 32 min). A
        /// delivery gap this long while tracking presumes the standard location
        /// session dead and restarts it on the next significant-change fix.
        public let recoveryGapS: Double

        enum CodingKeys: String, CodingKey {
            case walk, vehicles
            case recoveryGapS = "recovery_gap_s"
        }
    }

    // `Export` lives in TrackingConfigExport.swift — the §4.5 block carries the
    // recap's whole pacing model and both files stay inside the size budget.

    public let schemaVersion: Int
    public let filter: Filter
    public let segmentation: Segmentation
    public let dwell: Dwell
    public let simplify: Simplify
    public let matching: Matching
    public let photos: Photos
    public let photoImport: Import
    public let geocode: Geocode
    public let trip: Trip
    public let sampling: Sampling
    public let export: Export

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case filter, segmentation, dwell, simplify, matching, photos, geocode, trip, sampling, export
        case photoImport = "import"
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
