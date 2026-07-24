import Foundation

/// Typed mirror of Config/TrackingConfig.json — the single home for every
/// tunable (spec §0 rule 2: no magic numbers in code).
/// Every property is non-optional: a missing key is a hard startup error.
public struct TrackingConfig: Decodable, Equatable {
    public struct Filter: Decodable, Equatable {
        /// Samples with horizontal accuracy worse than this are discarded.
        public let maxHAccM: Double
        /// Samples worse than this still draw the route but are excluded as
        /// speed evidence: the 2026-07-18 drive had a glitch cluster at
        /// h_acc 43–49 m (under the keep threshold) that CoreLocation tagged
        /// with 137 m/s speeds, putting 495 km/h in the trip stats.
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
        /// Trip-end stop derivation (ADR 2026-07-18): a sample-silence gap at
        /// least this long with displacement ≤ radius_m is a stop the live
        /// detector could never see — iOS stops delivering fixes when the
        /// phone is stationary under a distance filter.
        public let gapMinS: Double
        /// A walk segment bracketed by vehicle segments counts as a stop
        /// ("park and walk around") when it lasts at least visit_min_s and
        /// ends within visit_return_radius_m of where it began — loop
        /// closure, not wander extent: trailhead loops range far and still
        /// end back at the car.
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

    /// Sendable: `OSRMMatchProvider` carries this across its async transport.
    public struct Matching: Decodable, Equatable, Sendable {
        /// OSRM host for map matching (§4.4), e.g. "http://127.0.0.1:5000".
        /// Empty string = matching disabled: segments keep raw geometry and
        /// readers fall back to the simplified raw polyline. Stays empty
        /// until the self-hosted server exists (`Docs/osrm-setup.md`).
        public let baseURL: String
        /// Max trackpoints per /match request (spec §4.4: ≤100).
        public let chunkSize: Int
        /// A segment whose worst per-matching confidence is below this keeps
        /// its raw polyline (spec §4.4: render "inferred", never invent roads).
        public let confidenceMin: Double
        /// Floor for the per-point search radius sent to OSRM; a point's own
        /// h_acc is used when it is larger.
        public let radiusM: Double
        /// Per-request timeout. Matching is best-effort and must never block
        /// trip completion (§4.4), so this stays short.
        public let timeoutS: Double
        /// Douglas-Peucker ε for *matched* geometry in the recap. Tighter
        /// than simplify.epsilon_m: 15 m would visibly cut snapped corners
        /// at recap zoom, but raw OSRM output on a long trip would blow the
        /// §4.5 render budget.
        public let displayEpsilonM: Double

        enum CodingKeys: String, CodingKey {
            case baseURL = "base_url"
            case chunkSize = "chunk_size"
            case confidenceMin = "confidence_min"
            case radiusM = "radius_m"
            case timeoutS = "timeout_s"
            case displayEpsilonM = "display_epsilon_m"
        }

        public init(
            baseURL: String,
            chunkSize: Int,
            confidenceMin: Double,
            radiusM: Double,
            timeoutS: Double,
            displayEpsilonM: Double
        ) {
            self.baseURL = baseURL
            self.chunkSize = chunkSize
            self.confidenceMin = confidenceMin
            self.radiusM = radiusM
            self.timeoutS = timeoutS
            self.displayEpsilonM = displayEpsilonM
        }
    }

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
        /// Watchdog for silent background-session death (2026-07-19 drive:
        /// the region-exit wake restarted GPS, iOS suspended the app ~10 s
        /// later, and 32 min of driving vanished). While actively tracking,
        /// a delivery gap of at least this long means the standard location
        /// session is presumed dead and gets restarted on the next fix that
        /// does arrive (significant-change monitoring keeps those coming).
        public let recoveryGapS: Double

        enum CodingKeys: String, CodingKey {
            case walk, vehicles
            case recoveryGapS = "recovery_gap_s"
        }
    }

    public struct Export: Decodable, Equatable {
        /// Recap video pipeline tunables (§4.5).
        public let targetDurationS: Double
        public let fps: Int
        public let stopHoldS: Double
        /// Stop holds shrink proportionally once they would exceed this share
        /// of the video, so stop-dense trips keep a nonzero travel budget.
        public let maxHoldFraction: Double
        public let gifFps: Int
        public let gifWidthPx: Int
        /// Output frame size (§4.5: 1080×1920, 9:16 social default).
        public let frameWidthPx: Int
        public let frameHeightPx: Int
        /// Ground span during the close follow-cam body (§4.5 step 1, prototype
        /// §2.3) — the tight end the camera zooms into; title/end widen out.
        public let cameraSpanM: Double
        /// Multiplier on the trip bounding box for the wide establishing/closing
        /// shots (1.0 = edge-to-edge). Floored at `cameraSpanM` on tiny trips.
        public let wideSpanPadding: Double
        /// Seconds to ease wide↔close at each card boundary (title→body,
        /// body→end). A quick cross-fade dolly; keep short or it eats the body.
        public let zoomTransitionS: Double
        /// Rotate the map heading-up (true TravelBoast). Needs a provider that
        /// honors `bearing` (MapLibre); false until the substrate switch (§3).
        public let followHeadingUp: Bool
        /// One map snapshot per this many frames; frames in between cross-fade
        /// the neighboring keyframe snapshots (§4.5 step 2 render budget).
        public let keyframeIntervalFrames: Int
        /// Trip chrome windows (§4.5 step 4): title card over the opening,
        /// end card ("Get this route") over the close.
        public let titleCardS: Double
        public let endCardS: Double
        /// H.264 average bitrate; unconstrained AVAssetWriter output measured
        /// 51 MB per 30 s (2026-07-19) — unshareable.
        public let videoBitrateMbps: Double

        public init(
            targetDurationS: Double,
            fps: Int,
            stopHoldS: Double,
            maxHoldFraction: Double,
            gifFps: Int,
            gifWidthPx: Int,
            frameWidthPx: Int,
            frameHeightPx: Int,
            cameraSpanM: Double,
            wideSpanPadding: Double,
            zoomTransitionS: Double,
            followHeadingUp: Bool,
            keyframeIntervalFrames: Int,
            titleCardS: Double,
            endCardS: Double,
            videoBitrateMbps: Double
        ) {
            self.targetDurationS = targetDurationS
            self.fps = fps
            self.stopHoldS = stopHoldS
            self.maxHoldFraction = maxHoldFraction
            self.gifFps = gifFps
            self.gifWidthPx = gifWidthPx
            self.frameWidthPx = frameWidthPx
            self.frameHeightPx = frameHeightPx
            self.cameraSpanM = cameraSpanM
            self.wideSpanPadding = wideSpanPadding
            self.zoomTransitionS = zoomTransitionS
            self.followHeadingUp = followHeadingUp
            self.keyframeIntervalFrames = keyframeIntervalFrames
            self.titleCardS = titleCardS
            self.endCardS = endCardS
            self.videoBitrateMbps = videoBitrateMbps
        }

        enum CodingKeys: String, CodingKey {
            case targetDurationS = "target_duration_s"
            case fps
            case stopHoldS = "stop_hold_s"
            case maxHoldFraction = "max_hold_fraction"
            case gifFps = "gif_fps"
            case gifWidthPx = "gif_width_px"
            case frameWidthPx = "frame_width_px"
            case frameHeightPx = "frame_height_px"
            case cameraSpanM = "camera_span_m"
            case wideSpanPadding = "wide_span_padding"
            case zoomTransitionS = "zoom_transition_s"
            case followHeadingUp = "follow_heading_up"
            case keyframeIntervalFrames = "keyframe_interval_frames"
            case titleCardS = "title_card_s"
            case endCardS = "end_card_s"
            case videoBitrateMbps = "video_bitrate_mbps"
        }
    }

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
