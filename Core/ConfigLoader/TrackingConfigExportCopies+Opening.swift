import Foundation

/// The copy a frozen-card film builds its camera with (#275, ADR file
/// 2026-10-10): the opening's held frame lasts the title card plus the
/// departure's photographs, which play over it. Its own file because the other
/// copy files are at their length limit.
extension TrackingConfig.Export {
    /// A copy whose opening frame is held for `seconds` (`title_card_s`).
    public func withTitleCardS(_ seconds: Double) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction, frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
            cameraSpanM: cameraSpanM, wideSpanPadding: wideSpanPadding,
            targetZoomRatio: targetZoomRatio, cameraAreaSplitRatio: cameraAreaSplitRatio,
            cameraContext: cameraContext, travelPacing: travelPacing, endRouteHoldS: endRouteHoldS,
            zoomTransitionS: zoomTransitionS, actSplitKm: actSplitKm,
            crossingBeatS: crossingBeatS, crossingApexPadding: crossingApexPadding,
            departureStopMaxPhotos: departureStopMaxPhotos, followHeadingUp: followHeadingUp,
            headingSmoothingDistanceM: headingSmoothingDistanceM,
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
            subjectLengthPx: subjectLengthPx, titleCardS: seconds,
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
            standardDurationMaxS: standardDurationMaxS,
            recapMode: recapMode, pipeline: pipeline
        )
    }
}
