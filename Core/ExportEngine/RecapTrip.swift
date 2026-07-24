import CoreGraphics
import Foundation

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

    /// Display-grade route polyline (matched + simplified upstream).
    public let route: [RecapCoordinate]
    public let stops: [Stop]
    public let title: String
    public let subtitle: String
    public let statsLines: [String]
    public let callToAction: String
    /// The share payload the end-card QR encodes — a string, not a rendered QR.
    /// The overlay renderer generates the (deterministic) QR from it at draw time.
    public let shareURL: String

    public init(
        route: [RecapCoordinate],
        stops: [Stop],
        title: String,
        subtitle: String,
        statsLines: [String],
        callToAction: String,
        shareURL: String
    ) {
        self.route = route
        self.stops = stops
        self.title = title
        self.subtitle = subtitle
        self.statsLines = statsLines
        self.callToAction = callToAction
        self.shareURL = shareURL
    }
}
