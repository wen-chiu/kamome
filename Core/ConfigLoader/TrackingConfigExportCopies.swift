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
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos, recapMode: recapMode
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
            tierStandardPhotos: tierStandardPhotos, tierTopPhotos: tierTopPhotos, recapMode: recapMode
        )
    }

}
