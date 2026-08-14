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
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm, followHeadingUp: resolved,
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
            keyframeIntervalFrames: keyframeIntervalFrames, titleCardS: titleCardS,
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
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm, followHeadingUp: followHeadingUp,
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
            keyframeIntervalFrames: keyframeIntervalFrames, titleCardS: titleCardS,
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
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm, followHeadingUp: followHeadingUp,
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
            keyframeIntervalFrames: keyframeIntervalFrames, titleCardS: titleCardS,
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
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm, followHeadingUp: followHeadingUp,
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
            keyframeIntervalFrames: keyframeIntervalFrames, titleCardS: titleCardS,
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
