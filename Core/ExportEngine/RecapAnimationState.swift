import CoreGraphics
import Foundation

/// The style-independent **state types** — the "narrow waist" where story/timing
/// meets rendering (render-layers refactor 2026-07-24). The animation timeline
/// produces these as pure functions of time; the renderers consume them. Neither
/// side depends on the other, so one timeline renders in any visual style.
///
/// (Defined ahead of the timeline + renderer migration so the boundaries can be
/// reviewed before `LinearTimeline` and the per-frame loop are built on them.)

/// What the map is framed at, at an instant. (Isometric/cinematic tilt is a
/// Phase 4 addition — it returns here with a `supportsPitch` capability when a
/// renderer can actually honor it; no dead field ships now.)
public struct CameraFrame: Equatable {
    public let centerLat: Double
    public let centerLon: Double
    /// Ground span (zoom): the horizontal meters the frame covers.
    public let spanM: Double
    /// Heading-up rotation, degrees, 0 = north-up.
    public let bearing: Double

    public init(centerLat: Double, centerLon: Double, spanM: Double, bearing: Double) {
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.spanM = spanM
        self.bearing = bearing
    }
}

/// The moving subject's state at an instant — where it is and which way it faces.
/// Motion belongs to the timeline; this is only the sampled state a renderer draws.
public struct SubjectState: Equatable {
    public let lat: Double
    public let lon: Double
    /// Travel bearing, degrees (the route tangent).
    public let heading: Double
    /// 0…1 presentation weight — e.g. the subject scaling up at a stop. MVP = 1.
    public let emphasis: Double
    /// Hidden during pure-chrome beats (title / finale) if a style wants that.
    public let isVisible: Bool

    public init(lat: Double, lon: Double, heading: Double, emphasis: Double = 1, isVisible: Bool = true) {
        self.lat = lat
        self.lon = lon
        self.heading = heading
        self.emphasis = emphasis
        self.isVisible = isVisible
    }
}

/// Style-independent map presentation at an instant — an opacity for intro /
/// outro fades and future cross-fades. *Which* concrete style renders is a
/// `MapRenderer` / `VisualStyle` concern, never the timeline's, so no style id
/// leaks in here. MVP: constant 1.
public struct MapState: Equatable {
    public let opacity: Double

    public init(opacity: Double = 1) {
        self.opacity = opacity
    }
}

/// The photos a stop shows (by reference), which one is in focus, and the
/// deck's presence (0…1) at this instant. The camera zoom that accompanies a
/// deck is a `CameraTrack` concern — this is only what the deck *draws*.
public struct RecapPhotoDeck: Equatable {
    public let photos: [PhotoRef]
    public let focusIndex: Int
    public let emphasis: Double

    public init(photos: [PhotoRef], focusIndex: Int, emphasis: Double) {
        self.photos = photos
        self.focusIndex = focusIndex
        self.emphasis = emphasis
    }
}

/// One drawable element active at an instant — **pure data**, no CoreGraphics
/// and no geo→pixel (the renderer projects through the `CameraFrame`, resolves
/// `PhotoRef`s, and generates the QR from `shareURL`). Overlays never mutate or
/// override the camera; the timeline synchronizes any camera move with the
/// content it belongs to. `Equatable`, so a test can assert what the timeline
/// produced without comparing bitmaps.
public enum OverlayContent: Equatable {
    /// The glowing traveled trail up to the subject.
    case routeReveal([RecapCoordinate])
    /// A stop pin + name label anchored on the map.
    case stopLabel(name: String, coordinate: RecapCoordinate, detail: String?)
    /// The enlarged photo deck at a stop.
    case photoDeck(RecapPhotoDeck)
    /// Opening chrome: trip name + dates/distance.
    case titleChrome(title: String, subtitle: String)
    /// Closing chrome: stats + the "Get this route" share payload (the renderer
    /// makes the QR).
    case endChrome(stats: [String], callToAction: String, shareURL: String)
}
