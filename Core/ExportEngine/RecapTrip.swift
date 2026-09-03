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

/// A lat/lon extent for the camera to frame — the opening establishing shot's
/// widest view (Chiu 2026-07-30).
///
/// Deliberately **not** part of `RecapTrip`: it is neither trip content nor
/// visual style but a fact about which map region is installed, so it travels
/// beside the trip rather than inside it. The app resolves it once
/// (`RecapMapRegion`); the camera receives four numbers and never learns that
/// regions or tile files exist.
public struct RecapBounds: Equatable {
    public let minLat: Double
    public let minLon: Double
    public let maxLat: Double
    public let maxLon: Double

    public init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }
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
        /// **There is no road here** — routing answered, and no road joins this
        /// leg's ends (`SegmentRoutability.noRoad`). A ferry, a flight, an island
        /// hop. The film gives it its own beat and a contained camera arc
        /// (`Docs/camera-arcs.md` §3).
        ///
        /// **Separate from `provenance` on purpose.** A crossing is dashed, so
        /// provenance already says `.inferred` — but so is every leg the provider
        /// was never asked about, and most of those are roads. Provenance answers
        /// "how honest is this line?"; this answers "is this a journey between
        /// places?", and only the second may move the camera.
        ///
        /// **Deliberately not derived from length.** Measured 2026-08-30: on the
        /// Iceland dump, 20 gaps exceed `act_split_km`, all of them photograph
        /// gaps inside long drives. An arc per gap is the 2026-08-02 act-camera
        /// defect rebuilt (`Docs/camera-arcs.md` §0).
        ///
        /// Defaults to `false`, which is what "nothing was established" must
        /// mean: a leg nobody asked about is never flown.
        public let isCrossing: Bool

        public init(
            coordinates: [RecapCoordinate],
            mode: TransportMode,
            provenance: RouteProvenance,
            isCrossing: Bool = false
        ) {
            self.coordinates = coordinates
            self.mode = mode
            self.provenance = provenance
            self.isCrossing = isCrossing
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

    /// **The two dates the Journey Card prints** — the last photograph taken
    /// before the crossing and the first taken after it (Chiu 2026-09-02).
    ///
    /// **Formatted copy, not `Date`s**, which is the convention every other
    /// string here follows (`subtitle`, `statsLines`, `Stop.dayLabel`):
    /// localization lives in the app layer and never enters `KamomeExportEngine`.
    /// A `Date` would drag date formatting — and a locale — into the renderer.
    ///
    /// **nil is a real answer and the card honours it.** Kamome has no departure
    /// or arrival *time* and never prints one (`CLAUDE.md` rule 5); when it does
    /// not have the dates either — no crossing, or photographs with no `taken_at`
    /// — the pass prints its distance row without them rather than inventing a
    /// date to fill the space.
    public let crossingDates: CrossingDates?

    /// The two dates, as the app formatted them.
    public struct CrossingDates: Equatable {
        /// The last photograph before the flight.
        public let departure: String
        /// The first photograph after it.
        public let arrival: String

        public init(departure: String, arrival: String) {
            self.departure = departure
            self.arrival = arrival
        }
    }

    /// Whether routing answered — with any of its three verdicts — for **every**
    /// leg of this trip.
    ///
    /// The one input `RecapFilmType` needs that the legs cannot supply
    /// themselves: `Leg.isCrossing` is a Bool, and it reads NULL as `false`
    /// deliberately, so a trip whose crossing was never routed is indexed from
    /// its legs as though it had none. This is what separates "no crossings" from
    /// "no answers".
    ///
    /// **Defaults to false**, which is the honest reading for every caller that
    /// does not know — synthetic fixtures, benchmarks, golden frames. They then
    /// classify `.unknown` and render the local film, which is exactly what they
    /// render today.
    public let everyLegRoutabilityEstablished: Bool

    /// Which of the three films this is (`RecapFilmType`). Derived, never stored
    /// — see that type for why the `stop.kind` pattern does not apply here.
    public var filmType: RecapFilmType {
        RecapFilmType.classify(legs: legs, everyLegEstablished: everyLegRoutabilityEstablished)
    }

    public init(
        legs: [Leg],
        stops: [Stop],
        title: String,
        subtitle: String,
        statsLines: [String],
        callToAction: String,
        shareURL: String? = nil,
        crossingDates: CrossingDates? = nil,
        everyLegRoutabilityEstablished: Bool = false
    ) {
        self.legs = legs
        self.stops = stops
        self.title = title
        self.subtitle = subtitle
        self.statsLines = statsLines
        self.callToAction = callToAction
        self.shareURL = shareURL
        self.crossingDates = crossingDates
        self.everyLegRoutabilityEstablished = everyLegRoutabilityEstablished
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
