import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// The one-time opening establishing sequence (Chiu 2026-07-30).
///
/// **Why the film needed it.** It used to open on the first route segment, so a
/// viewer met a glowing line before knowing what country they were looking at.
/// The prologue answers *where* before it shows *what*: the whole
/// country/island, then the trip's region, then the route — each eased into the
/// next, then held long enough to read.
///
/// **This is the only camera movement in the film.** Once the route is framed the
/// camera holds still, per act, north-up, exactly as before (Chiu 2026-07-25 —
/// a moving map hides the route's real shape and the distance covered). There is
/// deliberately no per-stop approach: a stop is told by the pin and the card, and
/// the two-beat presentation already gives it presence without flying the map.
extension CameraPath {
    /// One held framing in the opening.
    struct Beat {
        let frame: CameraFrame
        let holdS: Double
    }

    /// The opening as a sequence of held framings joined by eased transitions.
    ///
    /// **Beats that do not move are dropped** (Chiu 2026-07-31). A trip that fits
    /// in one act frames its region and its route identically, so the "regional →
    /// route" transition moved nothing and the two holds either side of it were a
    /// frozen picture — 6.4 s of a film in which literally nothing changed, right
    /// before the first stop. A list of beats with near-duplicates collapsed
    /// spends time only where the camera is actually going somewhere.
    struct Prologue {
        let beats: [Beat]
        let transitionS: Double

        /// When the wide beats are done — the moment the journey's clock starts
        /// and the closing zoom into the body camera begins.
        var totalS: Double {
            beats.reduce(0) { $0 + $1.holdS } + Double(max(beats.count - 1, 0)) * transitionS
        }

        /// The last wide framing — what the closing zoom eases *from*.
        var finalFrame: CameraFrame {
            beats.last?.frame ?? CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0)
        }

        /// The framing at `time`. Holds, then eases, then holds — the same
        /// smoothstep the act seams use, so the opening feels like the rest of the
        /// film rather than a separate title sequence.
        func frame(atTime time: Double) -> CameraFrame {
            guard let first = beats.first else {
                return CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0)
            }
            var cursor = 0.0
            for (index, beat) in beats.enumerated() {
                if time <= cursor + beat.holdS { return beat.frame }
                cursor += beat.holdS
                guard index + 1 < beats.count else { return beat.frame }
                let next = beats[index + 1].frame
                if time < cursor + transitionS {
                    return CameraPath.lerp(beat.frame, next, CameraPath.smoothstepPublic((time - cursor) / transitionS))
                }
                cursor += transitionS
            }
            return beats.last?.frame ?? first.frame
        }
    }

    /// Builds the **wide** half of the opening: country, then region.
    ///
    /// `establishing` is the installed map region's own extent — the honest
    /// country/island unit, and never wider than the tiles we have. Without it
    /// (no vector tiles, so Apple's map renders) the country view falls back to
    /// the trip's own bounds widened by `country_view_padding`, which is the most
    /// an offline app can claim to know about the surrounding geography.
    ///
    /// **The third beat is gone** (Chiu 2026-08-01). It used to be a stored copy
    /// of the first act's frame, held for `opening_route_s` with the vehicle
    /// still pinned at distance zero — a picture in which, by construction,
    /// nothing on screen could move. `CameraPath` now zooms from the last wide
    /// beat straight into the live follow camera while the journey is already
    /// running, so the opening resolves *onto* motion instead of into a freeze.
    ///
    /// `bodySpanM` is passed only so a wide beat that already frames the body
    /// tightly can collapse against it; the body's own framing stays live.
    static func buildWideOpening(
        route: [Point],
        establishing: RecapBounds?,
        config: TrackingConfig.Export,
        bodySpanM: Double
    ) -> Prologue {
        let tripBounds = bounds(of: route)
        let regional = frame(for: tripBounds, config: config, padding: config.wideSpanPadding)

        let countryBounds: Bounds
        if let establishing {
            countryBounds = Bounds(
                minLat: min(establishing.minLat, tripBounds.minLat),
                maxLat: max(establishing.maxLat, tripBounds.maxLat),
                minLon: min(establishing.minLon, tripBounds.minLon),
                maxLon: max(establishing.maxLon, tripBounds.maxLon)
            )
        } else {
            countryBounds = tripBounds
        }
        let countryPadding = establishing == nil
            ? config.countryViewPadding
            : config.wideSpanPadding
        let country = frame(for: countryBounds, config: config, padding: countryPadding)

        let wanted = [
            Beat(frame: country, holdS: config.openingCountryS),
            Beat(frame: regional, holdS: config.openingRegionalS)
        ]
        return Prologue(beats: collapse(wanted, config: config), transitionS: config.zoomTransitionS)
    }

    /// Drops beats that would not move the camera. When two consecutive framings
    /// are effectively the same picture, the later one wins — it is the one
    /// closest to the journey starting, and it carries the shorter hold, so the
    /// film gets on with it instead of sitting on a duplicate.
    static func collapse(_ beats: [Beat], config: TrackingConfig.Export) -> [Beat] {
        var kept: [Beat] = []
        for beat in beats {
            guard let previous = kept.last else { kept.append(beat); continue }
            if isEffectivelyTheSame(previous.frame, beat.frame, config: config) {
                kept[kept.count - 1] = beat
            } else {
                kept.append(beat)
            }
        }
        return kept
    }

    /// Two framings the eye cannot tell apart: near-identical zoom *and* centre.
    /// Both matter — a pan at the same zoom is still movement worth spending time
    /// on, and a zoom in place likewise.
    static func isEffectivelyTheSame(
        _ lhs: CameraFrame, _ rhs: CameraFrame, config: TrackingConfig.Export
    ) -> Bool {
        guard lhs.spanM > 0, rhs.spanM > 0 else { return true }
        let zoomRatio = max(lhs.spanM, rhs.spanM) / min(lhs.spanM, rhs.spanM)
        guard zoomRatio <= config.openingCollapseZoomRatio else { return false }
        let driftM = Geo.distanceM(
            latA: lhs.centerLat, lonA: lhs.centerLon, latB: rhs.centerLat, lonB: rhs.centerLon
        )
        return driftM <= min(lhs.spanM, rhs.spanM) * config.openingCollapseDriftFraction
    }

    /// A camera frame that fits `bounds`, floored at `camera_span_m` so a tiny
    /// extent does not zoom absurdly close.
    static func frame(for bounds: Bounds, config: TrackingConfig.Export, padding: Double) -> CameraFrame {
        CameraFrame(
            centerLat: (bounds.minLat + bounds.maxLat) / 2,
            centerLon: (bounds.minLon + bounds.maxLon) / 2,
            spanM: max(config.cameraSpanM, fittingSpanM(bounds: bounds, config: config) * padding),
            bearing: 0
        )
    }

    /// Interpolation between two framings.
    ///
    /// **Span moves geometrically, not linearly** — this is what made the opening
    /// zoom look janky. Zoom is perceived as a ratio: dropping from a 1,500 km
    /// country view to a 350 km regional one by equal metre-steps burns most of
    /// the apparent scale change in the first third and then crawls. Stepping by
    /// equal *ratios* makes the rate of apparent zoom constant, which is what
    /// every map library's flyTo does and what reads as smooth.
    ///
    /// Centre still lerps linearly; small lat/lon moves are safe here because a
    /// prologue never crosses the antimeridian, both frames coming from one
    /// region's extent.
    static func lerp(_ from: CameraFrame, _ to: CameraFrame, _ fraction: Double) -> CameraFrame {
        let span: Double
        if from.spanM > 0, to.spanM > 0 {
            span = from.spanM * pow(to.spanM / from.spanM, fraction)
        } else {
            span = from.spanM + (to.spanM - from.spanM) * fraction
        }
        return CameraFrame(
            centerLat: from.centerLat + (to.centerLat - from.centerLat) * fraction,
            centerLon: from.centerLon + (to.centerLon - from.centerLon) * fraction,
            spanM: span,
            bearing: 0
        )
    }
}
