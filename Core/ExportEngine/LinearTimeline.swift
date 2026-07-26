import Foundation
import KamomeConfig

/// The one story shape the Replay MVP ships: **linear** — establishing → travel
/// legs → stops → finale, in trip order (render-layers refactor 2026-07-24). A
/// concrete struct (no `SceneDirector` / `Scene` / `TimelineCompiler` ceremony —
/// there is exactly one story shape) that directly produces the four
/// style-independent state streams the renderers consume:
///
///   `cameraFrame(atTime:)` · `subjectState(atTime:)` · `mapState(atTime:)` · `overlayContents(atTime:)`
///
/// It reuses `CameraPath`'s speed-warp / hold / easing math for subject motion
/// and framing, and adds the stop choreography: at each stop the `photoDeck`
/// overlay opens on its own reveal envelope (grow `deckZoomS` → hold
/// `n·deckPhotoHoldS` → shrink `deckZoomS`).
///
/// The camera does **not** move for a stop (Chiu 2026-07-25). It holds the act's
/// fixed frame throughout; a stop is told by the label and the card, not by
/// flying the map. Overlays never touch the camera.
///
/// When a smart `SceneDirector` arrives (Phase 4, deterministic, spec §7), it
/// slots in above this; the state streams and renderers do not change.
public struct LinearTimeline {
    public let durationS: Double
    /// Total rendered frames (`durationS · fps`) — what the render loop and
    /// exporter iterate; taken straight from the reused `CameraPath`.
    public let frameCount: Int

    private let path: CameraPath
    private let stops: [RecapTrip.Stop]
    private let holds: [CameraPath.Hold]
    private let routeCoordinates: [RecapCoordinate]
    private let deck: RecapDeck
    private let titleCardS: Double
    private let endCardS: Double
    private let title: String
    private let subtitle: String
    private let statsLines: [String]
    private let callToAction: String
    private let shareURL: String

    /// Fails on the same degenerate input as `CameraPath` (no usable route).
    public init?(trip: RecapTrip, config: TrackingConfig.Export) {
        let routePoints = trip.route.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stopPoints = trip.stops.map { CameraPath.Point(lat: $0.coordinate.lat, lon: $0.coordinate.lon) }
        guard let path = CameraPath(
            route: routePoints, stops: stopPoints, config: config, stopHoldsS: trip.stops.map(\.dwellS)
        ) else { return nil }

        self.path = path
        durationS = path.durationS
        frameCount = path.frameCount
        stops = trip.stops
        holds = path.holds
        routeCoordinates = trip.route
        deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
        titleCardS = min(config.titleCardS, path.durationS)
        endCardS = config.endCardS
        title = trip.title
        subtitle = trip.subtitle
        statsLines = trip.statsLines
        callToAction = trip.callToAction
        shareURL = trip.shareURL
    }

    // MARK: - The four state streams

    /// Subject motion (the route tangent) — straight from the reused CameraPath.
    public func subjectState(atTime time: Double) -> SubjectState {
        let position = path.position(atTime: time)
        return SubjectState(lat: position.lat, lon: position.lon, heading: position.heading)
    }

    /// Map presentation. MVP: fully opaque throughout (fades are a later addition).
    public func mapState(atTime time: Double) -> MapState {
        MapState(opacity: 1)
    }

    /// Camera framing: straight through to `CameraPath`, which holds one fixed
    /// frame per act. Nothing here modulates it — not the stop, not the deck.
    public func cameraFrame(atTime time: Double) -> CameraFrame {
        let frame = path.cameraFrame(atTime: time)
        return CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon,
            spanM: frame.spanM, bearing: frame.bearing
        )
    }

    /// Everything drawn over the map at `time`: the revealed trail, the trip
    /// chrome, and — at a stop — the two beats. Beat 1: the pin lands with its
    /// name floating above the vehicle. Beat 2: the photo deck opens (focus
    /// advancing through the rotate phase, the card growing on `deckReveal`)
    /// while the lead-in label cross-fades out, its identity handed to the pin +
    /// name drawn under the card.
    public func overlayContents(atTime time: Double) -> [OverlayContent] {
        var contents: [OverlayContent] = [.routeReveal(routePrefix(atTime: time))]
        if time < titleCardS {
            contents.append(.titleChrome(title: title, subtitle: subtitle))
        }
        if time >= durationS - endCardS {
            contents.append(.endChrome(stats: statsLines, callToAction: callToAction, shareURL: shareURL))
        }
        if let active = activeStop(atTime: time), !active.stop.photos.isEmpty {
            let stop = active.stop
            let window = deckWindow(active.hold)
            let labelOpacity = leadLabelOpacity(atTime: time, deck: window)
            if labelOpacity > 0.001 {
                contents.append(.stopLabel(
                    name: stop.name, coordinate: stop.coordinate, detail: stop.detail, opacity: labelOpacity
                ))
            }
            if time >= window.start {
                contents.append(.photoDeck(RecapPhotoDeck(
                    photos: stop.photos,
                    focusIndex: focusIndex(atTime: time, deck: window, count: stop.photos.count),
                    reveal: deckReveal(atTime: time, deck: window),
                    opacity: deckOpacity(atTime: time, deck: window),
                    name: stop.name,
                    detail: stop.detail,
                    coordinate: stop.coordinate
                )))
            }
        }
        return contents
    }

    // MARK: - Stop choreography (overlay only — the camera holds still)

    private func activeStop(atTime time: Double) -> (hold: CameraPath.Hold, stop: RecapTrip.Stop)? {
        for hold in holds where hold.startS <= time && time < hold.endS {
            guard stops.indices.contains(hold.stopIndex) else { continue }
            return (hold, stops[hold.stopIndex])
        }
        return nil
    }

    /// The deck's sub-window inside a stop's hold: the label leads for
    /// `labelLeadS`, then the photo card owns the rest.
    private func deckWindow(_ hold: CameraPath.Hold) -> (start: Double, end: Double) {
        (min(hold.startS + deck.labelLeadS, hold.endS), hold.endS)
    }

    /// The zoom ramp used at both edges of a deck window, clamped to 40% of the
    /// window so it always fits even when a stop-dense trip squeezed the hold
    /// (`max_hold_fraction`).
    private func zoomRamp(_ window: (start: Double, end: Double)) -> Double {
        min(deck.zoomS, (window.end - window.start) * 0.4)
    }

    /// **Card** envelope (Chiu 2026-07-25): the photo keeps growing across the
    /// whole hold — not just the camera's dolly-in — so the stop plays as a slow
    /// cinematic reveal rather than a card that pops to full size and sits
    /// there. It scales back down over the closing ramp as the scene closes.
    private func deckReveal(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let zoom = zoomRamp(window)
        let openEnd = window.end - zoom
        let opening = openEnd - window.start
        guard opening > 0 else { return 0 }
        if time <= openEnd { return Self.smoothstep((time - window.start) / opening) }
        guard zoom > 0 else { return 0 }
        return Self.smoothstep((window.end - time) / zoom)
    }

    /// Card opacity: fades in over the opening ramp, out over the closing one.
    private func deckOpacity(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let zoom = zoomRamp(window)
        guard zoom > 0 else { return time >= window.start ? 1 : 0 }
        if time < window.start + zoom { return Self.smoothstep((time - window.start) / zoom) }
        if time > window.end - zoom { return Self.smoothstep((window.end - time) / zoom) }
        return 1
    }

    /// The lead-in label above the vehicle: solid through beat 1, then handing
    /// the stop's identity to the card's own pin + name as the deck fades in.
    private func leadLabelOpacity(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        guard time >= window.start else { return 1 }
        let zoom = zoomRamp(window)
        guard zoom > 0 else { return 0 }
        return 1 - Self.smoothstep((time - window.start) / zoom)
    }

    /// Which photo is in focus: the rotate phase (between the zoom edges) split
    /// into `count` equal slots. Grow holds photo 0 (highlight leads); shrink
    /// holds the last.
    private func focusIndex(atTime time: Double, deck window: (start: Double, end: Double), count: Int) -> Int {
        let zoom = zoomRamp(window)
        let rotateStart = window.start + zoom
        let rotateLength = max((window.end - zoom) - rotateStart, 1e-6)
        let slot = rotateLength / Double(count)
        return min(max(Int((time - rotateStart) / slot), 0), count - 1)
    }

    private func routePrefix(atTime time: Double) -> [RecapCoordinate] {
        path.routePrefix(atTime: time).map { RecapCoordinate(lat: $0.lat, lon: $0.lon) }
    }

    private static func smoothstep(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
