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
/// It reuses `CameraPath`'s speed-warp / hold / easing math for camera framing
/// and subject motion, and adds the stop choreography: at each stop the camera
/// **dollies in** to `deckSpanM` and the `photoDeck` overlay blooms, both driven
/// by one shared 0…1 emphasis envelope (grow `deckZoomS` → hold `n·deckPhotoHoldS`
/// → shrink `deckZoomS`). The deck zoom lives here, in the camera stream —
/// overlays never touch the camera.
///
/// When a smart `SceneDirector` arrives (Phase 4, deterministic, spec §7), it
/// slots in above this; the state streams and renderers do not change.
public struct LinearTimeline {
    public let durationS: Double

    private let path: CameraPath
    private let stops: [RecapTrip.Stop]
    private let holds: [CameraPath.Hold]
    private let routeCoordinates: [RecapCoordinate]
    private let deck: RecapDeck
    private let deckSpanM: Double
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
        stops = trip.stops
        holds = path.holds
        routeCoordinates = trip.route
        deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
        deckSpanM = config.deckSpanM
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

    /// Camera framing: the CameraPath wide→close follow, with the stop dolly-in
    /// laid on top. The label-lead beat stays at the follow span (no dolly); over
    /// the deck sub-window the span eases to `deckSpanM` and back, on the shared
    /// emphasis envelope.
    public func cameraFrame(atTime time: Double) -> CameraFrame {
        let base = path.cameraFrame(atTime: time)
        guard let active = activeStop(atTime: time), !active.stop.photos.isEmpty else {
            return CameraFrame(centerLat: base.centerLat, centerLon: base.centerLon, spanM: base.spanM, bearing: base.bearing)
        }
        let emphasis = deckEmphasis(atTime: time, deck: deckWindow(active.hold))
        let spanM = base.spanM + (deckSpanM - base.spanM) * emphasis
        return CameraFrame(centerLat: base.centerLat, centerLon: base.centerLon, spanM: spanM, bearing: base.bearing)
    }

    /// Everything drawn over the map at `time`: the revealed trail, the trip
    /// chrome, and — at a stop — the two-beat: the stop label leads across the
    /// whole stop, then the photo deck blooms over the deck sub-window (focus
    /// advancing through the rotate phase, emphasis on the camera's envelope).
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
            contents.append(.stopLabel(name: stop.name, coordinate: stop.coordinate, detail: stop.detail))
            let window = deckWindow(active.hold)
            if time >= window.start {
                contents.append(.photoDeck(RecapPhotoDeck(
                    photos: stop.photos,
                    focusIndex: focusIndex(atTime: time, deck: window, count: stop.photos.count),
                    emphasis: deckEmphasis(atTime: time, deck: window)
                )))
            }
        }
        return contents
    }

    // MARK: - Stop choreography (shared by camera + overlay so they stay in sync)

    private func activeStop(atTime time: Double) -> (hold: CameraPath.Hold, stop: RecapTrip.Stop)? {
        for hold in holds where hold.startS <= time && time < hold.endS {
            guard stops.indices.contains(hold.stopIndex) else { continue }
            return (hold, stops[hold.stopIndex])
        }
        return nil
    }

    /// The deck's sub-window inside a stop's hold: the label leads for
    /// `labelLeadS`, then the deck (dolly + photos) owns the rest.
    private func deckWindow(_ hold: CameraPath.Hold) -> (start: Double, end: Double) {
        (min(hold.startS + deck.labelLeadS, hold.endS), hold.endS)
    }

    /// 0 at the sub-window edges, 1 across the middle — the grow → hold → shrink
    /// envelope. Zoom clamps to 40% of the sub-window so it always fits even when
    /// a stop-dense trip squeezed the hold (`max_hold_fraction`).
    private func deckEmphasis(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let length = window.end - window.start
        let zoom = min(deck.zoomS, length * 0.4)
        guard zoom > 0 else { return time >= window.start ? 1 : 0 }
        if time < window.start + zoom { return Self.smoothstep((time - window.start) / zoom) }
        if time > window.end - zoom { return Self.smoothstep((window.end - time) / zoom) }
        return 1
    }

    /// Which photo is in focus: the rotate phase (between the zoom edges) split
    /// into `count` equal slots. Grow holds photo 0 (highlight leads); shrink
    /// holds the last.
    private func focusIndex(atTime time: Double, deck window: (start: Double, end: Double), count: Int) -> Int {
        let length = window.end - window.start
        let zoom = min(deck.zoomS, length * 0.4)
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
