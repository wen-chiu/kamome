import Foundation

/// The §4.5 recap-export block, split out of `TrackingConfig.swift` so both files
/// stay inside the size budget. It carries the film's entire pacing model: frame
/// size, the opening prologue, stop dwell bounds, and the target duration window.
public extension TrackingConfig {
    public struct Export: Decodable, Equatable {
        /// Recap video pipeline tunables (§4.5).
        public let targetDurationS: Double
        public let fps: Int
        public let stopHoldS: Double
        /// Stop holds shrink proportionally past this share of the video, so
        /// stop-dense trips keep a nonzero travel budget.
        public let maxHoldFraction: Double
        public let gifFps: Int
        public let gifWidthPx: Int
        /// Output frame size (§4.5: 1080×1920, 9:16 social default).
        public let frameWidthPx: Int
        public let frameHeightPx: Int
        /// Ground span of the close follow-cam body (§4.5 step 1, prototype §2.3).
        public let cameraSpanM: Double
        /// Trip-bounding-box multiplier for the wide shots; floored at `cameraSpanM`.
        public let wideSpanPadding: Double
        /// Seconds to ease wide↔close at each card boundary (a quick dolly).
        public let zoomTransitionS: Double
        /// Split the film into a new fixed camera frame when consecutive route
        /// points are more than this far apart — a flight, a ferry, or a drive
        /// resuming in another region. Everything short of that plays inside one
        /// held frame (Chiu 2026-07-25: a still map is what makes the distance
        /// covered legible).
        public let actSplitKm: Double
        /// Rotate the map heading-up (needs a `bearing`-honoring provider; §3).
        public let followHeadingUp: Bool
        /// Photo-deck pacing (§5): label lead, per-photo dwell, grow/shrink each,
        /// dolly-in span while a stop's deck is up (deck zoom = camera track).
        public let deckPhotoHoldS: Double
        public let deckZoomS: Double
        public let deckLabelLeadS: Double
        /// How long the subject takes to park on arriving at a stop, and to pull
        /// away again when the next leg starts (§5, Chiu 2026-07-26). A stop is a
        /// scene, not a visibility toggle: the car hands the stop's identity over
        /// to the pin as it fades, and takes it back as it returns. Long enough
        /// to read as parking, short enough not to eat the stop's own beat.
        public let subjectParkS: Double
        /// The one-time opening prologue (Chiu 2026-07-30): the film establishes
        /// *where* before it shows *what*. Country/island extent, then the trip's
        /// region, then the route — each eased into the next over
        /// `zoom_transition_s`. This is the **only** camera movement in the film;
        /// once the route is framed the camera holds still per act, north-up
        /// (Chiu 2026-07-25, unchanged).
        public let openingCountryS: Double
        public let openingRegionalS: Double
        public let openingRouteS: Double
        /// Per-stop dwell bounds. Stops are deliberately *not* given equal time —
        /// a photo-rich stop earns more (`RecapDurationPlan`) — but neither a
        /// single-photo stop nor an eight-photo one should leave this window.
        public let stopDwellMinS: Double
        public let stopDwellMaxS: Double
        /// The film's target length. Duration follows content rather than a fixed
        /// number: a flat 30 s gave a six-stop trip 2.5 s per stop, which is a
        /// montage, not a journey.
        public let totalDurationMinS: Double
        public let totalDurationMaxS: Double
        /// One map snapshot per this many frames; in-between frames cross-fade (§4.5).
        public let keyframeIntervalFrames: Int
        /// Trip chrome windows (§4.5 step 4): title over the open, end over the close.
        public let titleCardS: Double
        public let endCardS: Double
        /// H.264 average bitrate; unconstrained output was ~51 MB/30 s (unshareable).
        public let videoBitrateMbps: Double

        public init(
            targetDurationS: Double, fps: Int, stopHoldS: Double, maxHoldFraction: Double,
            gifFps: Int, gifWidthPx: Int, frameWidthPx: Int, frameHeightPx: Int,
            cameraSpanM: Double, wideSpanPadding: Double, zoomTransitionS: Double,
            actSplitKm: Double, followHeadingUp: Bool,
            deckPhotoHoldS: Double, deckZoomS: Double, deckLabelLeadS: Double, subjectParkS: Double,
            openingCountryS: Double, openingRegionalS: Double, openingRouteS: Double,
            stopDwellMinS: Double, stopDwellMaxS: Double,
            totalDurationMinS: Double, totalDurationMaxS: Double,
            keyframeIntervalFrames: Int, titleCardS: Double, endCardS: Double, videoBitrateMbps: Double
        ) {
            self.targetDurationS = targetDurationS; self.fps = fps
            self.stopHoldS = stopHoldS; self.maxHoldFraction = maxHoldFraction
            self.gifFps = gifFps; self.gifWidthPx = gifWidthPx
            self.frameWidthPx = frameWidthPx; self.frameHeightPx = frameHeightPx
            self.cameraSpanM = cameraSpanM; self.wideSpanPadding = wideSpanPadding
            self.zoomTransitionS = zoomTransitionS; self.actSplitKm = actSplitKm
            self.followHeadingUp = followHeadingUp
            self.deckPhotoHoldS = deckPhotoHoldS; self.deckZoomS = deckZoomS
            self.deckLabelLeadS = deckLabelLeadS
            self.subjectParkS = subjectParkS
            self.openingCountryS = openingCountryS
            self.openingRegionalS = openingRegionalS
            self.openingRouteS = openingRouteS
            self.stopDwellMinS = stopDwellMinS
            self.stopDwellMaxS = stopDwellMaxS
            self.totalDurationMinS = totalDurationMinS
            self.totalDurationMaxS = totalDurationMaxS
            self.keyframeIntervalFrames = keyframeIntervalFrames; self.titleCardS = titleCardS
            self.endCardS = endCardS; self.videoBitrateMbps = videoBitrateMbps
        }

        /// A copy with `follow_heading_up` forced to `resolved`. The composition
        /// root resolves the configured request against what the base-map
        /// renderer can actually honor, so a provider
        /// that cannot rotate is never handed a bearing it would silently drop.
        public func withFollowHeadingUp(_ resolved: Bool) -> Export {
            Export(
                targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
                maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
                frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
                cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
                zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm, followHeadingUp: resolved,
                deckPhotoHoldS: deckPhotoHoldS, deckZoomS: deckZoomS,
                deckLabelLeadS: deckLabelLeadS,
                subjectParkS: subjectParkS,
                openingCountryS: openingCountryS,
                openingRegionalS: openingRegionalS,
                openingRouteS: openingRouteS,
                stopDwellMinS: stopDwellMinS,
                stopDwellMaxS: stopDwellMaxS,
                totalDurationMinS: totalDurationMinS,
                totalDurationMaxS: totalDurationMaxS,
                keyframeIntervalFrames: keyframeIntervalFrames, titleCardS: titleCardS,
                endCardS: endCardS, videoBitrateMbps: videoBitrateMbps
            )
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
            case actSplitKm = "act_split_km"
            case followHeadingUp = "follow_heading_up"
            case deckPhotoHoldS = "deck_photo_hold_s"
            case deckZoomS = "deck_zoom_s"
            case deckLabelLeadS = "deck_label_lead_s"
            case subjectParkS = "subject_park_s"
            case openingCountryS = "opening_country_s"
            case openingRegionalS = "opening_regional_s"
            case openingRouteS = "opening_route_s"
            case stopDwellMinS = "stop_dwell_min_s"
            case stopDwellMaxS = "stop_dwell_max_s"
            case totalDurationMinS = "total_duration_min_s"
            case totalDurationMaxS = "total_duration_max_s"
            case keyframeIntervalFrames = "keyframe_interval_frames"
            case titleCardS = "title_card_s"
            case endCardS = "end_card_s"
            case videoBitrateMbps = "video_bitrate_mbps"
        }
    }
}
