import Foundation

/// **The JSON key mapping for `TrackingConfig.Export`**, lifted out of the type
/// itself on 2026-09-01.
///
/// Purely mechanical: every case here is one snake_case name in
/// `Config/TrackingConfig.json`. It moved because `TrackingConfigExport.swift`
/// had reached its 400-line limit exactly, so the next tunable — whichever it
/// turned out to be — had to split something. The mapping is the part with no
/// behaviour in it, which makes it the right part to move, and it follows the
/// split this type already uses for its initialiser and its copy helpers.
extension TrackingConfig.Export {
    enum CodingKeys: String, CodingKey {
        case cameraPanWindowFractionPerS = "camera_pan_window_fraction_per_s"
        case cameraDeadZoneFraction = "camera_dead_zone_fraction"
        case cameraSafeZoneFraction = "camera_safe_zone_fraction"
        case cameraResponsiveness = "camera_responsiveness"
        case endRevealS = "end_reveal_s"
        case endRevealPadding = "end_reveal_padding"
        case endCardStyle = "end_card_style"
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
        case targetZoomRatio = "target_zoom_ratio"
        case zoomTransitionS = "zoom_transition_s"
        case actSplitKm = "act_split_km"
        case crossingBeatS = "crossing_beat_s"
        case crossingApexPadding = "crossing_apex_padding"
        case departureStopMaxPhotos = "departure_stop_max_photos"
        case followHeadingUp = "follow_heading_up"
        case deckPhotoHoldS = "deck_photo_hold_s"
        case deckPhotoMinHoldS = "deck_photo_min_hold_s"
        case deckZoomS = "deck_zoom_s"
        case deckLabelLeadS = "deck_label_lead_s"
        case subjectParkS = "subject_park_s"
        case openingCountryS = "opening_country_s"
        case openingRegionalS = "opening_regional_s"
        case countryViewPadding = "country_view_padding"
        case openingCollapseZoomRatio = "opening_collapse_zoom_ratio"
        case openingCollapseDriftFraction = "opening_collapse_drift_fraction"
        case firstStopDwellScale = "first_stop_dwell_scale"
        case stopDwellMinS = "stop_dwell_min_s"
        case stopDwellMaxS = "stop_dwell_max_s"
        case totalDurationMinS = "total_duration_min_s"
        case totalDurationMaxS = "total_duration_max_s"
        case keyframeIntervalFrames = "keyframe_interval_frames"
        case snapshotStationMaxMagnification = "snapshot_station_max_magnification"
        case crossingFlightMaxLongitudeDeg = "crossing_flight_max_longitude_deg"
        case snapshotStationPadding = "snapshot_station_padding"
        case subjectLengthPx = "subject_length_px"
        case titleCardS = "title_card_s"
        case endCardS = "end_card_s"
        case videoBitrateMbps = "video_bitrate_mbps"
        case stopWeightingEnabled = "stop_weighting_enabled"
        case waypointMaxPhotos = "waypoint_max_photos"
        case waypointMaxDwellS = "waypoint_max_dwell_s"
        case waypointHoldS = "waypoint_hold_s"
        case uncappedPhotoHoldS = "uncapped_photo_hold_s"
        case allocationZeroShare = "allocation_zero_share"
        case allocationOneShare = "allocation_one_share"
        case allocationTwoShare = "allocation_two_share"
        case allocationMaxPhotos = "allocation_max_photos"
        case favoriteWeight = "favorite_weight"
        case tierTopShare = "tier_top_share"
        case tierStandardPhotos = "tier_standard_photos"
        case tierTopPhotos = "tier_top_photos"
        case earnedStopsFloor = "earned_stops_floor"
        case earnedStopsCap = "earned_stops_cap"
        case earnedStopsPerDoubling = "earned_stops_per_doubling"
        case earnedStopsReferenceTripStops = "earned_stops_reference_trip_stops"
        case recapMode = "recap_mode"
    }
}
