import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **The opening, the body span and the journey's clock — assembled in the one
/// order their dependencies allow**, lifted out of `CameraPath.init` on
/// 2026-09-02.
///
/// Pure statics over arguments, so the move widened no stored property and cost
/// the type no encapsulation — the same split `CameraPathCore` made, and made for
/// the same two reasons: `CameraPath.swift` had exactly one line of headroom
/// under its size budget, and its initializer was over the function-length one.
///
/// **The order is the content.** The opening is built first and the body span is
/// derived from it (Chiu 2026-08-09): `body = established / target_zoom_ratio`,
/// where `established` is the *last* wide beat (2026-08-31). Only then can the
/// closing-zoom handoff and the journey's start and end be sized, because each of
/// those depends on the one before it.
extension CameraPath {
    /// What `openingPlan` needs from the initializer — grouped so the call
    /// reads as one value instead of seven positional arguments.
    struct OpeningRequest {
        /// Built before this call, because the body span is derived from it.
        let prologue: Prologue?
        let route: [Point]
        let establishing: RecapBounds?
        let config: TrackingConfig.Export
        let bodySpanM: Double
        /// The world the body camera starts in — the route's on a one-area film,
        /// the first area's otherwise — for where the closing zoom lands.
        let bodyBounds: Bounds
        let totalDurationS: Double
        let journeyEndsBeforeS: Double
        /// The opening is a single held frame containing both ends of a flight,
        /// and the crossing arc — not a closing zoom — is what leaves it.
        let opensOnTheFlight: Bool
    }

    /// Where the opening ends and the journey begins — everything `CameraPath.init`
    /// used to compute as six separate `let`s between the body span and the
    /// journey timeline.
    struct OpeningPlan {
        let prologue: Prologue?
        let wideEndS: Double
        let openingEndsS: Double
        let revealS: Double
        let journeyEndS: Double
    }

    /// Everything the assembly needs from the initializer.
    struct OpeningAssembly {
        let route: [Point]
        let cumulativeM: [Double]
        let anchors: [(stopIndex: Int, distanceM: Double)]
        let totalM: Double
        let crossingVertexRanges: [Range<Int>]
        let stopHoldsS: [Double]?
        let totalDurationS: Double
        let establishing: RecapBounds?
        let openingS: Double
        let journeyEndsBeforeS: Double
        let openingFlightFrame: CameraFrame?
        let config: TrackingConfig.Export
    }

    struct AssembledOpening {
        let crossings: [Crossing]
        let bodySpanM: Double
        let plan: OpeningPlan
        /// The opening is a single held flight frame, and the crossing arc — not
        /// a closing zoom — is what leaves it.
        let opensOnTheFlight: Bool
        /// The local journey the film is actually about: the whole route on a
        /// local trip, and the stretch after the crossing on a type-2 one. Both
        /// the body span and the end reveal are fitted to it.
        let destinationJourney: [Point]
        /// The areas the body is framed in — nil for a one-area film, whose body
        /// is `bodySpanM` throughout (`CameraPathAreas`).
        let areaPlan: AreaPlan?
    }

    static func openingAndBodySpan(_ request: OpeningAssembly) -> AssembledOpening {
        let route = request.route, config = request.config

        let builtPrologue = wideOpening(
            openingS: request.openingS, route: route,
            crossings: request.crossingVertexRanges, establishing: request.establishing,
            config: config, flightFrame: request.openingFlightFrame
        )
        let opensOnTheFlight = request.openingFlightFrame != nil && request.openingS > 0
        let crossings = crossings(vertexRanges: request.crossingVertexRanges, cumulativeM: request.cumulativeM)

        // The destination's own local journey is what the body span divides on a
        // type-2 film, whose one opening beat spans two countries.
        let destination = openingRoute(route: route, crossings: request.crossingVertexRanges)
        let span = bodySpan(BodySpanRequest(
            prologue: builtPrologue, route: route, anchors: request.anchors, totalM: request.totalM,
            crossings: crossings, stopHoldsS: request.stopHoldsS,
            totalDurationS: request.totalDurationS, establishing: request.establishing, config: config,
            establishedSpanOverrideM: opensOnTheFlight
                ? frame(for: bounds(of: destination), config: config,
                        padding: config.wideSpanPadding).spanM
                : nil
        ))

        // The areas, when there is more than one: then the first area's span is
        // what the opening hands to, and the one-span `span` above is not used.
        let areaPlan = AreaPlan.make(AreaRequest(
            route: route, cumulativeM: request.cumulativeM, anchors: request.anchors,
            crossings: crossings, establishing: request.establishing, config: config,
            durationS: request.totalDurationS,
            timeline: { reframes, areas in
                buildTimelineWithReframes(
                    anchors: request.anchors, totalM: request.totalM, config: config,
                    stopHoldsS: request.stopHoldsS, crossings: crossings,
                    startS: 0, targetS: request.totalDurationS, reframes: reframes, areas: areas
                )
            }
        ))
        let firstSpan = areaPlan?.areas[0].spanM ?? span

        let plan = openingPlan(OpeningRequest(
            prologue: builtPrologue, route: route, establishing: request.establishing, config: config,
            bodySpanM: firstSpan, bodyBounds: areaPlan?.areas[0].bounds ?? bounds(of: route),
            totalDurationS: request.totalDurationS,
            journeyEndsBeforeS: request.journeyEndsBeforeS, opensOnTheFlight: opensOnTheFlight
        ))
        return AssembledOpening(
            crossings: crossings, bodySpanM: firstSpan, plan: plan,
            opensOnTheFlight: opensOnTheFlight, destinationJourney: destination, areaPlan: areaPlan
        )
    }
}
