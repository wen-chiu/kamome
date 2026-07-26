import CoreGraphics
import Foundation
import KamomeTrackingEngine

/// A neutral lat/lon pair for the render pipeline — the style-independent trip
/// data speaks in coordinates, not in any renderer's point type.
public struct RecapCoordinate: Equatable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// A *pointer* to an image, not the image itself — the data layer never holds a
/// rendered bitmap (that would couple it to a resolution + memory layout). The
/// rendering layer resolves a `PhotoRef` to a `CGImage` at draw size through an
/// app-provided resolver (PhotoKit can't live in the SDK-free core). `Equatable`
/// so the timeline's output can be asserted without comparing pixels.
public enum PhotoRef: Equatable {
    /// A PhotoKit asset by its local identifier (recorded / imported trips).
    case asset(String)
    /// An on-disk image.
    case file(URL)
}

/// How a stretch of route came to have the shape it has (Fable review
/// 2026-07-26, PD-1). **Release-critical, not bookkeeping:** the published film
/// is the public artifact, so honesty has to be a property of the *pixels*, not
/// of a label elsewhere in the app. A viewer looking at a Kamome recap must be
/// able to tell "Kamome watched me drive this" from "Kamome's best guess at how
/// I got between these two photos."
///
/// Derived, not stored — the schema has no confidence column and needs none:
/// snapped geometry exists or it doesn't, and the segment knows whether it was
/// recorded or reconstructed from photos.
public enum RouteProvenance: Equatable, Sendable {
    /// GPS Kamome actually recorded. Drawn solid.
    case recorded
    /// Snapped to the real road network — a recorded trace through `/match`, or
    /// a photo-EXIF leg routed through `/route`. Drawn solid: the road is real
    /// even though the traveling wasn't watched.
    case reconstructed
    /// Raw geometry that was never recorded and could not be reconstructed:
    /// straight lines between photo positions, because OSRM was unreachable,
    /// refused the leg, or the leg is a walk we deliberately never routed.
    /// **Drawn dashed** — this is the honest half of PD-1/PD-2.
    case inferred

    /// The film must visibly distinguish this stretch from confident route.
    public var isInferred: Bool { self == .inferred }
}

/// Style-independent trip data (render-layers refactor 2026-07-24): the single
/// input the animation timeline consumes. Everything here is *content*, never
/// *look* — route geometry, stops with their names / photos / dwell, and the
/// chrome copy. How any of it is drawn is a downstream style concern, so the
/// same `RecapTrip` can render as TravelBoast, modern-minimal, or cinematic.
///
/// Built by `RecapComposer` from the trip DB (photos pre-loaded, copy localized
/// in the app layer); replaces the old `RecapComposer.Content`.
public struct RecapTrip {
    /// A stop the film pauses at. `dwellS` is the photo-count-driven hold (§5,
    /// `RecapDeck.dwellS`) — a timing fact about the trip, so it lives here and
    /// the timeline reads it, not a renderer.
    public struct Stop: Equatable {
        public let coordinate: RecapCoordinate
        public let name: String
        public let dayLabel: String
        public let detail: String?
        public let photos: [PhotoRef]
        public let dwellS: Double

        public init(
            coordinate: RecapCoordinate,
            name: String,
            dayLabel: String,
            detail: String? = nil,
            photos: [PhotoRef] = [],
            dwellS: Double
        ) {
            self.coordinate = coordinate
            self.name = name
            self.dayLabel = dayLabel
            self.detail = detail
            self.photos = photos
            self.dwellS = dwellS
        }
    }

    /// One stretch of the journey with a single story about itself: its
    /// geometry, how it was traveled, and where that geometry came from.
    ///
    /// The route used to be one flat polyline, which could only ever make one
    /// claim about the whole trip. A real imported trip is not uniform — a
    /// motorway leg reconstructs confidently while the walk at the end of it
    /// never will — so provenance has to survive as far as the renderer.
    public struct Leg: Equatable {
        /// Display-grade polyline (matched + simplified upstream).
        public let coordinates: [RecapCoordinate]
        /// How this stretch was traveled. Carried through the waist because the
        /// data has it; multi-modal *animation* is deliberately deferred, so no
        /// renderer draws a walk differently from a drive yet.
        public let mode: TransportMode
        public let provenance: RouteProvenance

        public init(coordinates: [RecapCoordinate], mode: TransportMode, provenance: RouteProvenance) {
            self.coordinates = coordinates
            self.mode = mode
            self.provenance = provenance
        }
    }

    /// The journey, leg by leg, in travel order.
    public let legs: [Leg]
    /// The whole display polyline — every leg concatenated. Consecutive legs
    /// share an endpoint, so the duplicate vertex contributes zero length and
    /// the camera's distance math is unaffected.
    public var route: [RecapCoordinate] { legs.flatMap(\.coordinates) }
    public let stops: [Stop]
    public let title: String
    public let subtitle: String
    public let statsLines: [String]
    public let callToAction: String
    /// The share payload the end card encodes as a QR — a string, not a
    /// rendered QR; the overlay renderer generates the (deterministic) code at
    /// draw time.
    ///
    /// **nil for the Replay MVP** (PD-4). The only payload we could produce is
    /// `kamome://route/<id>`, which resolves to nothing: scanning it does not
    /// open the trip, install the app, or reach a page. A QR that does nothing
    /// is worse than no QR — it invites the one interaction the film can't
    /// honor. The end card shows a wordmark instead; the capability returns
    /// unchanged the day the share URL exists (spec P6/P7).
    public let shareURL: String?

    public init(
        legs: [Leg],
        stops: [Stop],
        title: String,
        subtitle: String,
        statsLines: [String],
        callToAction: String,
        shareURL: String? = nil
    ) {
        self.legs = legs
        self.stops = stops
        self.title = title
        self.subtitle = subtitle
        self.statsLines = statsLines
        self.callToAction = callToAction
        self.shareURL = shareURL
    }

    /// A trip that is one recorded drive end to end — synthetic geometry in
    /// benchmarks and golden-frame fixtures, where there is nothing to
    /// distinguish. Real trips come through `RecapComposer` with real legs.
    public init(
        route: [RecapCoordinate],
        stops: [Stop],
        title: String,
        subtitle: String,
        statsLines: [String],
        callToAction: String,
        shareURL: String? = nil
    ) {
        self.init(
            legs: [Leg(coordinates: route, mode: .drive, provenance: .recorded)],
            stops: stops, title: title, subtitle: subtitle, statsLines: statsLines,
            callToAction: callToAction, shareURL: shareURL
        )
    }
}
