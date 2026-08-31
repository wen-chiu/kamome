import Foundation

/// The memberwise initialiser for `TrackingConfig.Export`, split out of
/// `TrackingConfigExport.swift` for the same reason its copy helpers were: the
/// §4.5 export block has more tunables than one file's length budget allows,
/// and a 50-parameter initialiser is most of it. Behaviour is unchanged.
extension TrackingConfig.Export {
        public init(
            targetDurationS: Double, fps: Int, stopHoldS: Double, maxHoldFraction: Double,
            gifFps: Int, gifWidthPx: Int, frameWidthPx: Int, frameHeightPx: Int,
            cameraSpanM: Double, wideSpanPadding: Double, targetZoomRatio: Double = 2.5,
            zoomTransitionS: Double,
            actSplitKm: Double, crossingBeatS: Double, crossingApexPadding: Double, followHeadingUp: Bool,
            cameraPanWindowFractionPerS: Double, cameraDeadZoneFraction: Double, cameraSafeZoneFraction: Double,
            cameraResponsiveness: Double, endRevealS: Double, endRevealPadding: Double, endCardStyle: String,
            deckPhotoHoldS: Double, deckPhotoMinHoldS: Double, deckZoomS: Double, deckLabelLeadS: Double, subjectParkS: Double,
            openingCountryS: Double, openingRegionalS: Double, countryViewPadding: Double, firstStopDwellScale: Double,
            openingCollapseZoomRatio: Double, openingCollapseDriftFraction: Double,
            stopDwellMinS: Double, stopDwellMaxS: Double,
            totalDurationMinS: Double, totalDurationMaxS: Double,
            keyframeIntervalFrames: Int, subjectLengthPx: Double, titleCardS: Double, endCardS: Double, videoBitrateMbps: Double,
            stopWeightingEnabled: Bool, waypointMaxPhotos: Int, waypointMaxDwellS: Double, waypointHoldS: Double,
            uncappedPhotoHoldS: Double,
            allocationZeroShare: Double, allocationOneShare: Double,
            allocationTwoShare: Double, allocationMaxPhotos: Int, favoriteWeight: Double,
            tierTopShare: Double,
            tierStandardPhotos: Int, tierTopPhotos: Int,
            earnedStopsFloor: Int, earnedStopsCap: Int,
            earnedStopsPerDoubling: Double, earnedStopsReferenceTripStops: Int,
            recapMode: RecapMode
        ) {
            self.targetDurationS = targetDurationS; self.fps = fps
            self.stopHoldS = stopHoldS; self.maxHoldFraction = maxHoldFraction
            self.gifFps = gifFps; self.gifWidthPx = gifWidthPx
            self.frameWidthPx = frameWidthPx; self.frameHeightPx = frameHeightPx
            self.cameraSpanM = cameraSpanM; self.wideSpanPadding = wideSpanPadding
            self.targetZoomRatio = targetZoomRatio
            self.zoomTransitionS = zoomTransitionS; self.actSplitKm = actSplitKm
            self.crossingBeatS = crossingBeatS; self.crossingApexPadding = crossingApexPadding
            self.followHeadingUp = followHeadingUp
            self.cameraPanWindowFractionPerS = cameraPanWindowFractionPerS
            self.cameraDeadZoneFraction = cameraDeadZoneFraction
            self.cameraSafeZoneFraction = cameraSafeZoneFraction
            self.cameraResponsiveness = cameraResponsiveness
            self.endRevealS = endRevealS; self.endRevealPadding = endRevealPadding
            self.endCardStyle = endCardStyle
            self.deckPhotoHoldS = deckPhotoHoldS; self.deckPhotoMinHoldS = deckPhotoMinHoldS
            self.deckZoomS = deckZoomS
            self.deckLabelLeadS = deckLabelLeadS
            self.subjectParkS = subjectParkS
            self.openingCountryS = openingCountryS
            self.openingRegionalS = openingRegionalS
            self.countryViewPadding = countryViewPadding
            self.openingCollapseZoomRatio = openingCollapseZoomRatio
            self.openingCollapseDriftFraction = openingCollapseDriftFraction
            self.firstStopDwellScale = firstStopDwellScale
            self.stopDwellMinS = stopDwellMinS
            self.stopDwellMaxS = stopDwellMaxS
            self.totalDurationMinS = totalDurationMinS
            self.totalDurationMaxS = totalDurationMaxS
            self.keyframeIntervalFrames = keyframeIntervalFrames
            self.subjectLengthPx = subjectLengthPx; self.titleCardS = titleCardS
            self.endCardS = endCardS; self.videoBitrateMbps = videoBitrateMbps
            self.stopWeightingEnabled = stopWeightingEnabled
            self.waypointMaxPhotos = waypointMaxPhotos
            self.waypointMaxDwellS = waypointMaxDwellS
            self.waypointHoldS = waypointHoldS
            self.uncappedPhotoHoldS = uncappedPhotoHoldS
            self.allocationZeroShare = allocationZeroShare
            self.allocationOneShare = allocationOneShare
            self.allocationTwoShare = allocationTwoShare
            self.allocationMaxPhotos = allocationMaxPhotos
            self.favoriteWeight = favoriteWeight
            self.tierTopShare = tierTopShare
            self.tierStandardPhotos = tierStandardPhotos
            self.tierTopPhotos = tierTopPhotos
            self.earnedStopsFloor = earnedStopsFloor
            self.earnedStopsCap = earnedStopsCap
            self.earnedStopsPerDoubling = earnedStopsPerDoubling
            self.earnedStopsReferenceTripStops = earnedStopsReferenceTripStops
            self.recapMode = recapMode
        }
}
