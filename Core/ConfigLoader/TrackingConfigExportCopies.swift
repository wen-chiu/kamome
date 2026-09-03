import Foundation

/// Derived copies of `TrackingConfig.Export`.
///
/// Split out of `TrackingConfigExport.swift` purely for file length — the struct
/// plus its memberwise initialiser plus these copies exceeded the 400-line limit.
/// Behaviour is unchanged; each helper returns the same value it always did.
extension TrackingConfig.Export {
    /// A copy with `follow_heading_up` forced to `resolved`. The composition
    /// root resolves the configured request against what the base-map
    /// renderer can actually honor, so a provider
    /// that cannot rotate is never handed a bearing it would silently drop.
    public func withFollowHeadingUp(_ resolved: Bool) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: resolved,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS, endRevealPadding: endRevealPadding,
            endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS,
            deckLabelLeadS: deckLabelLeadS,
            subjectParkS: subjectParkS,
            openingCountryS: openingCountryS,
            openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding,
            firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS,
            stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalDurationMinS,
            totalDurationMaxS: totalDurationMaxS,
            keyframeIntervalFrames: keyframeIntervalFrames,
            snapshotStationMaxMagnification: snapshotStationMaxMagnification,
            snapshotStationPadding: snapshotStationPadding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: allocationZeroShare,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: recapMode
        )
    }

    /// A copy with the allocator's zero share overridden.
    ///
    /// **Variant A only.** `allocation_zero_share` (0.4 shipped) gives the bottom
    /// 40% of stops no photograph at all — right for Variant B, where the film is
    /// a highlight reel and a quiet stop earning only a pin is the point. It
    /// contradicts Variant A, whose whole claim is "see the whole trip": a stop
    /// with a beat and no photograph is still empty to the viewer, so keeping the
    /// stop while dropping its photographs keeps the timeline and loses the memory.
    ///
    /// Kept out of `RecapMode` itself because Variant A is a desk-review mode, not
    /// something the app ships. If it ever does ship, this belongs *in* the mode
    /// rather than in a harness override.
    public func withAllocationZeroShare(_ share: Double) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS,
            endRevealPadding: endRevealPadding, endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: deckLabelLeadS, subjectParkS: subjectParkS,
            openingCountryS: openingCountryS, openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding, firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalDurationMinS, totalDurationMaxS: totalDurationMaxS,
            keyframeIntervalFrames: keyframeIntervalFrames,
            snapshotStationMaxMagnification: snapshotStationMaxMagnification,
            snapshotStationPadding: snapshotStationPadding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: share,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: recapMode
        )
    }

    /// A copy in a different `RecapMode`. The desk MVP renders run **Variant A**
    /// (`.full` — every clustered stop presented, no duration cap) while the
    /// shipped default stays **Variant B** (`.highlight`), so the harness needs to
    /// ask for a mode without the config file being edited between runs and
    /// accidentally committed. Same shape as `withTotalDuration` above.
    public func withRecapMode(_ mode: RecapMode) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS,
            endRevealPadding: endRevealPadding, endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: deckLabelLeadS, subjectParkS: subjectParkS,
            openingCountryS: openingCountryS, openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding, firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalDurationMinS, totalDurationMaxS: totalDurationMaxS,
            keyframeIntervalFrames: keyframeIntervalFrames,
            snapshotStationMaxMagnification: snapshotStationMaxMagnification,
            snapshotStationPadding: snapshotStationPadding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: allocationZeroShare,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: mode
        )
    }

    /// A copy with the duration window overridden. Measurement aid for the
    /// duration-by-stop-count experiment (2026-08-04) — lets a sweep try
    /// several film lengths without rewriting the config file between runs.
    public func withTotalDuration(min minS: Double, max maxS: Double) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS,
            endRevealPadding: endRevealPadding, endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: deckLabelLeadS, subjectParkS: subjectParkS,
            openingCountryS: openingCountryS, openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding, firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: minS, totalDurationMaxS: maxS,
            keyframeIntervalFrames: keyframeIntervalFrames,
            snapshotStationMaxMagnification: snapshotStationMaxMagnification,
            snapshotStationPadding: snapshotStationPadding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: allocationZeroShare,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: recapMode
        )
    }

    /// A copy with a different keyframe interval. Measurement aid only
    /// (2026-08-15): export time is snapshot-bound, and this is the one number
    /// that changes the snapshot count without changing the film's content, so
    /// an audit can price a film at several intervals in one run instead of
    /// editing `TrackingConfig.json` between renders.
    ///
    /// Not a product switch. What a coarser interval buys in seconds it spends
    /// on cross-fade quality, which is Chiu's call, made against renders.
    /// How long a crossing beat plays, for a review render.
    ///
    /// **A desk knob, not a tuning result.** `crossing_beat_s` ships at 4.0 —
    /// the length the Journey Card needs to be read (ADR 2026-09-03) — and it
    /// must not be set from one fixture: Ishigaki is 272 km and Auckland is
    /// 8,732 km, so a constant that suits one makes the aircraft crawl or tear
    /// across the other. This exists so the same film can be rendered at several
    /// values and judged — the method `Docs/cross-region-journeys.md` insists on
    /// after `body_span_padding` and `tier_skip_share` were both reverse-derived
    /// from one trip and both removed.
    ///
    /// ⚠️ **The 4/6/9 sweep this was built for is closed** (Chiu 2026-09-02) and
    /// the screen-speed rule it validated is not to be re-run. What the knob is
    /// for now is judging the *card's* legibility at a length, which is what the
    /// beat measures since the retime.
    public func withCrossingBeatS(_ seconds: Double) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: seconds, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS,
            endRevealPadding: endRevealPadding, endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: deckLabelLeadS, subjectParkS: subjectParkS,
            openingCountryS: openingCountryS, openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding, firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalDurationMinS, totalDurationMaxS: totalDurationMaxS,
            keyframeIntervalFrames: keyframeIntervalFrames,
            snapshotStationMaxMagnification: snapshotStationMaxMagnification,
            snapshotStationPadding: snapshotStationPadding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: allocationZeroShare,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: recapMode
        )
    }

    /// A copy with the crop-scaling station budget replaced.
    ///
    /// Review-only, and it exists for one measurement: the interval-1 reference
    /// the P0 is judged against (`Docs/camera-arcs.md` §7). At magnification 1.0
    /// and padding 1.0 a station can hold exactly one camera value and its
    /// transform is the identity — which *is* interval 1, produced by the shipped
    /// loop rather than by a second code path kept alive to be compared with.
    public func withKeyframeIntervalFrames(_ frames: Int) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS,
            endRevealPadding: endRevealPadding, endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: deckLabelLeadS, subjectParkS: subjectParkS,
            openingCountryS: openingCountryS, openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding, firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalDurationMinS, totalDurationMaxS: totalDurationMaxS,
            keyframeIntervalFrames: frames,
            snapshotStationMaxMagnification: snapshotStationMaxMagnification,
            snapshotStationPadding: snapshotStationPadding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: allocationZeroShare,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: recapMode
        )
    }

    /// A copy with the crop-scaling station budget replaced.
    ///
    /// Review-only, and it exists for one measurement: the interval-1 reference
    /// the P0 is judged against (`Docs/camera-arcs.md` §7). At magnification 1.0
    /// and padding 1.0 a station can hold exactly one camera value and its
    /// transform is the identity — which *is* interval 1, produced by the shipped
    /// loop rather than by a second code path kept alive to be compared with.
    public func withSnapshotStations(maxMagnification: Double, padding: Double) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, gifFps: gifFps, gifWidthPx: gifWidthPx,
            frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: cameraPanWindowFractionPerS,
            cameraDeadZoneFraction: cameraDeadZoneFraction,
            cameraSafeZoneFraction: cameraSafeZoneFraction,
            cameraResponsiveness: cameraResponsiveness, endRevealS: endRevealS,
            endRevealPadding: endRevealPadding, endCardStyle: endCardStyle,
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: deckLabelLeadS, subjectParkS: subjectParkS,
            openingCountryS: openingCountryS, openingRegionalS: openingRegionalS,
            countryViewPadding: countryViewPadding, firstStopDwellScale: firstStopDwellScale,
            openingCollapseZoomRatio: openingCollapseZoomRatio,
            openingCollapseDriftFraction: openingCollapseDriftFraction,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalDurationMinS, totalDurationMaxS: totalDurationMaxS,
            keyframeIntervalFrames: keyframeIntervalFrames,
            snapshotStationMaxMagnification: maxMagnification,
            snapshotStationPadding: padding,
            crossingFlightMaxLongitudeDeg: crossingFlightMaxLongitudeDeg,
            subjectLengthPx: subjectLengthPx, titleCardS: titleCardS,
            endCardS: endCardS, videoBitrateMbps: videoBitrateMbps,
            stopWeightingEnabled: stopWeightingEnabled, waypointMaxPhotos: waypointMaxPhotos,
            waypointMaxDwellS: waypointMaxDwellS, waypointHoldS: waypointHoldS,
            uncappedPhotoHoldS: uncappedPhotoHoldS,
            allocationZeroShare: allocationZeroShare,
            allocationOneShare: allocationOneShare, allocationTwoShare: allocationTwoShare,
            allocationMaxPhotos: allocationMaxPhotos, favoriteWeight: favoriteWeight,
            tierTopShare: tierTopShare,
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos,
            earnedStopsFloor: earnedStopsFloor, earnedStopsCap: earnedStopsCap,
            earnedStopsPerDoubling: earnedStopsPerDoubling,
            earnedStopsReferenceTripStops: earnedStopsReferenceTripStops,
            recapMode: recapMode
        )
    }

}
