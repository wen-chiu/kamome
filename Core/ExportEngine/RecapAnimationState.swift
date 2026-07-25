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

/// The photos a stop shows (by reference), which one is in focus, how far the
/// **reveal** has opened, and the deck's opacity at this instant — plus the stop
/// identity the card carries below it (pin + name), so the viewer always knows
/// where a photo was taken.
///
/// `reveal` is the deck's own scale envelope (Chiu 2026-07-25): a 0…1 progress
/// the renderer maps onto its own on-screen size range, so the photo grows as
/// the shot opens. It is **synchronized with, but separate from**, the camera's
/// dolly into the stop — how big the photo draws is a drawing concern, how
/// zoomed the map is is a `CameraFrame` concern, and one value must never drive
/// both.
public struct RecapPhotoDeck: Equatable {
    public let photos: [PhotoRef]
    public let focusIndex: Int
    /// 0…1 reveal progress → the renderer's min…max on-screen card size.
    public let reveal: Double
    /// 0…1 fade, so the card can cross-fade with the lead-in stop label.
    public let opacity: Double
    /// The stop's name and optional detail line, drawn under the card.
    public let name: String
    public let detail: String?

    public init(
        photos: [PhotoRef], focusIndex: Int, reveal: Double, opacity: Double,
        name: String, detail: String? = nil
    ) {
        self.photos = photos
        self.focusIndex = focusIndex
        self.reveal = reveal
        self.opacity = opacity
        self.name = name
        self.detail = detail
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
    /// A stop pin on the map with its name label floating clear above the
    /// vehicle (the lead-in beat). `opacity` fades it out as the photo deck
    /// takes over the stop's identity below the card.
    case stopLabel(name: String, coordinate: RecapCoordinate, detail: String?, opacity: Double)
    /// The enlarged photo deck at a stop.
    case photoDeck(RecapPhotoDeck)
    /// Opening chrome: trip name + dates/distance.
    case titleChrome(title: String, subtitle: String)
    /// Closing chrome: stats + the "Get this route" share payload (the renderer
    /// makes the QR).
    case endChrome(stats: [String], callToAction: String, shareURL: String)
}
