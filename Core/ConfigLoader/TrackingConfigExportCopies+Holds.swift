import Foundation

/// The copy earned travel builds its second pass with (ADR file 2026-09-28).
/// Its own file because `TrackingConfigExportCopies.swift` is at its length limit.
extension TrackingConfig.Export {
    /// A copy whose stops may take `fraction` of the journey. Earned travel
    /// shortens the film by the travel its windows do not need; at the shipped
    /// `max_hold_fraction` the stops would then be scaled down to fit the shorter
    /// film (`CameraPath.cappedHolds`), taking the time out of the photographs
    /// instead of the road.
    public func withMaxHoldFraction(_ fraction: Double) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: stopHoldS,
            maxHoldFraction: fraction, frameWidthPx: frameWidthPx, frameHeightPx: frameHeightPx,
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
            standardDurationMaxS: standardDurationMaxS,
            recapMode: recapMode, pipeline: pipeline
        )
    }
}
