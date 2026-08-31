import CoreGraphics
import Foundation
import KamomeTrackingEngine

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
public struct CameraFrame: Hashable {
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
    /// 0…1 **presence**: how much of the subject is on screen right now. 1 while
    /// travelling; 0 while parked at a stop; in between during the park / pull-away
    /// transitions (Chiu 2026-07-26).
    ///
    /// Continuous rather than a boolean because a stop is a scene, not a toggle:
    /// the car has to *arrive and park*, handing the stop's identity to the pin as
    /// it goes, and pull away again as the next leg starts. A hard cut reads as the
    /// car being deleted. How presence is drawn is the renderer's business — alpha
    /// today, alpha plus a settle in scale if a style wants it later.
    public let emphasis: Double
    /// Hidden outright — fully parked, or a pure-chrome beat a style wants clear.
    public let isVisible: Bool
    /// **Which subject is on screen** — the trip's vehicle, or the one that
    /// crosses a leg with no road (`Docs/cross-region-journeys.md` requirement 4).
    ///
    /// A role, not a sprite. The timeline says "this stretch is being crossed";
    /// what that looks like is the renderer's business, exactly as `emphasis`
    /// says "half present" and not "50% alpha". This is where the split in
    /// `Docs/camera-arcs.md` §6 lands in code: the **camera** is one primitive
    /// and learns nothing about transport, while the **narration** is not
    /// unified and travels through the state stream that already carries the
    /// subject.
    public let role: SubjectRole

    /// The two subjects a film can put on screen.
    ///
    /// Two rather than a mode enum on purpose: **there is no classifier**
    /// (session 1 of 2, `Docs/eng-session-cross-region.md`). Every crossing gets
    /// the same subject, so there is nothing to tune and nothing to guess. When
    /// the plane/ship/seagull classifier arrives it decides which *art* the
    /// crossing role resolves to; it does not add cases here.
    public enum SubjectRole: Equatable, Sendable {
        case vehicle
        case crossing
    }

    public init(
        lat: Double, lon: Double, heading: Double,
        emphasis: Double = 1, isVisible: Bool = true, role: SubjectRole = .vehicle
    ) {
        self.lat = lat
        self.lon = lon
        self.heading = heading
        self.emphasis = emphasis
        self.isVisible = isVisible
        self.role = role
    }
}

/// Style-independent map presentation at an instant — an opacity for intro /
/// outro fades and future cross-fades. *Which* concrete style renders is a
/// `MapRenderer` / `VisualStyle` concern, never the timeline's, so no style id
/// leaks in here. MVP: constant 1.
public struct MapState: Hashable {
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
    ///
    /// **Which day it is and how far the journey has come are deliberately not
    /// here** (Chiu 2026-07-31). Those belong to the film, not to one photograph,
    /// so they live in the persistent `hud` overlay — on screen while driving as
    /// well as while stopped. A card that carried them repeated the HUD for a few
    /// seconds and then took them away again.
    public let name: String
    public let detail: String?
    /// Where the stop is. The renderer projects it and places the whole card
    /// group *beside the vehicle parked there* — with a static camera the
    /// vehicle is no longer centred, so a frame-centred card would collide with
    /// it (Chiu 2026-07-25).
    public let coordinate: RecapCoordinate

    public init(
        photos: [PhotoRef], focusIndex: Int, reveal: Double, opacity: Double,
        name: String, detail: String? = nil, coordinate: RecapCoordinate
    ) {
        self.photos = photos
        self.focusIndex = focusIndex
        self.reveal = reveal
        self.opacity = opacity
        self.name = name
        self.detail = detail
        self.coordinate = coordinate
    }
}

/// A revealed stretch of trail: the part of one `RecapTrip.Leg` the subject has
/// already covered, carrying that leg's mode and provenance so the renderer can
/// stroke it honestly. Pure data — the renderer projects and styles it.
public struct RecapRouteLeg: Equatable {
    public let coordinates: [RecapCoordinate]
    public let mode: TransportMode
    public let provenance: RouteProvenance

    public init(coordinates: [RecapCoordinate], mode: TransportMode, provenance: RouteProvenance) {
        self.coordinates = coordinates
        self.mode = mode
        self.provenance = provenance
    }
}

/// One drawable element active at an instant — **pure data**, no CoreGraphics
/// and no geo→pixel (the renderer projects through the `CameraFrame`, resolves
/// `PhotoRef`s, and generates the QR from `shareURL`). Overlays never mutate or
/// override the camera; the timeline synchronizes any camera move with the
/// content it belongs to. `Equatable`, so a test can assert what the timeline
/// produced without comparing bitmaps.
public enum OverlayContent: Equatable {
    /// The traveled trail up to the subject, leg by leg. Legs rather than one
    /// polyline because they do not all deserve the same stroke: a leg the
    /// pipeline could not confidently reconstruct must read as a guess in the
    /// published film, not as road (PD-1).
    case routeReveal([RecapRouteLeg])
    /// A stop pin on the map with its name label floating clear above the
    /// vehicle (the lead-in beat). `opacity` fades it out as the photo deck
    /// takes over the stop's identity below the card.
    case stopLabel(name: String, coordinate: RecapCoordinate, detail: String?, opacity: Double)
    /// The enlarged photo deck at a stop.
    case photoDeck(RecapPhotoDeck)
    /// **Persistent film chrome** (Chiu 2026-07-31): which day of the trip it is
    /// and how far the journey has come, in the frame's top corners, for the whole
    /// body of the film — driving as well as stopped.
    ///
    /// This is a fact about the *journey at this instant*, which is why it is one
    /// overlay rather than something each stop carries: the distance has to keep
    /// climbing while the car moves, and the day has to be readable on a leg that
    /// belongs to no stop at all. `place` is the stop the film is parked at, and
    /// is nil on the road between them.
    ///
    /// Suppressed under the title and end cards, which are full-bleed and own the
    /// frame for their few seconds.
    case hud(dayLabel: String, place: String?, travelledM: Double)
    /// Opening chrome: trip name + dates/distance.
    case titleChrome(title: String, subtitle: String)
    /// Closing chrome: stats, the call to action, and the share payload the
    /// renderer turns into a QR. `shareURL` is nil for the Replay MVP (PD-4) —
    /// the end card shows the Kamome wordmark instead of a code that resolves
    /// to nothing.
    case endChrome(stats: [String], callToAction: String, shareURL: String?)
}
