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
    /// The three framings the opening moves through, and how long each is held.
    struct Prologue {
        let country: CameraFrame
        let regional: CameraFrame
        let route: CameraFrame
        let countryS: Double
        let regionalS: Double
        let routeS: Double
        let transitionS: Double

        /// Where the journey's clock starts. Everything before this is prologue.
        var totalS: Double {
            countryS + transitionS + regionalS + transitionS + routeS
        }

        /// The framing at `time`, for `time < totalS`. Holds, then eases, then
        /// holds — the same smoothstep the act seams use, so the opening feels
        /// like the rest of the film rather than a separate title sequence.
        func frame(atTime time: Double) -> CameraFrame {
            let easeOut = countryS + transitionS
            let regionalEnd = easeOut + regionalS
            let easeIn = regionalEnd + transitionS

            if time <= countryS { return country }
            if time < easeOut {
                return CameraPath.lerp(country, regional, CameraPath.smoothstepPublic((time - countryS) / transitionS))
            }
            if time <= regionalEnd { return regional }
            if time < easeIn {
                return CameraPath.lerp(regional, route, CameraPath.smoothstepPublic((time - regionalEnd) / transitionS))
            }
            return route
        }
    }

    /// Builds the opening for a trip.
    ///
    /// `establishing` is the installed map region's own extent — the honest
    /// country/island unit, and never wider than the tiles we have. Without it
    /// (no vector tiles, so Apple's map renders) the country view falls back to
    /// the trip's own bounds widened by `country_view_padding`, which is the most
    /// an offline app can claim to know about the surrounding geography.
    static func buildPrologue(
        route: [Point],
        establishing: RecapBounds?,
        config: TrackingConfig.Export,
        routeFrame: CameraFrame
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

        return Prologue(
            country: country,
            regional: regional,
            route: routeFrame,
            countryS: config.openingCountryS,
            regionalS: config.openingRegionalS,
            routeS: config.openingRouteS,
            transitionS: config.zoomTransitionS
        )
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
