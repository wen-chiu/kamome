import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **Whether a crossing's flight can be drawn, decided before any snapshot is
/// taken** (Chiu 2026-09-01).
///
/// A type-2 film has two forms and **both are main paths**:
///
/// - **the flight is drawn** — the title card sits over a still frame holding
///   both places, the aircraft crosses it, and the camera then closes into the
///   destination;
/// - **the flight is not drawn** — the title card sits over a frozen frame of the
///   destination country and cuts straight into the local trip.
///
/// The second is not a degraded fallback. Taiwan → Iceland is past every limit
/// below, and the Iceland film is the project's most-judged trip.
///
/// ## Two layers, and they answer different questions
///
/// **This is the geometric layer**: pure arithmetic over two coordinates, no
/// MapKit, evaluated while the film's shape is still being chosen. It answers
/// *"should the film draw a flight?"*
///
/// The **capability layer** is `MapRendererCapabilities.maxFramableLongitudeDeg`
/// and the refusal in `MapKitSnapshotProvider.region`. It answers *"can this
/// substrate draw this frame?"*, and it is what makes the geometric layer
/// non-load-bearing: if the policy here were ever wrong, the substrate refuses
/// rather than crashing or silently drawing a picture nobody chose.
///
/// Neither replaces the other. A single config number cannot express the whole
/// rule, because **which limit binds first depends on where the pair is**: the
/// portrait aspect (a 9:16 frame is 1.778× taller than it is wide, so it runs off
/// the poles) binds at low latitudes, and MapKit's zoom floor binds at high ones.
/// Measured 2026-09-01: Taipei → Helsinki fails the aspect limit at 96.6° while
/// Taipei → Paris fails the zoom floor at 119.2°.
public enum CrossingFraming {
    /// Why a flight is not being drawn, for the log line that says so.
    ///
    /// An enum rather than a Bool because these are different facts about the
    /// journey and a reader may want to act on them differently — and because a
    /// silent `false` is how the last five one-film-at-a-time defects happened
    /// (`Arch.md` §6).
    public enum Refusal: String, Equatable, Sendable, CaseIterable {
        /// Further apart than the film draws, though a frame may well exist.
        case beyondFilmPolicy
        /// Wider than this substrate will render at all.
        case beyondSubstrate
        /// A frame this wide is taller than the planet in this aspect ratio.
        case tallerThanThePlanet
    }

    public enum Verdict: Equatable, Sendable {
        case drawTheFlight
        case frozenCard(Refusal)

        public var drawsTheFlight: Bool { self == .drawTheFlight }
    }

    /// Can the film draw this crossing?
    ///
    /// - Parameter substrateMaxLongitudeDeg: the renderer's own declared ceiling
    ///   (`MapRendererCapabilities.maxFramableLongitudeDeg`). nil means the
    ///   substrate claims no limit — `FlatSnapshotProvider` does not have one —
    ///   and then only the policy and the aspect decide.
    public static func verdict(
        from origin: RecapCoordinate,
        to destination: RecapCoordinate,
        config: TrackingConfig.Export,
        substrateMaxLongitudeDeg: Double?
    ) -> Verdict {
        let longitudeApart = abs(destination.lon - origin.lon)
        guard longitudeApart <= config.crossingFlightMaxLongitudeDeg else {
            return .frozenCard(.beyondFilmPolicy)
        }
        if let substrateMaxLongitudeDeg, longitudeApart > substrateMaxLongitudeDeg {
            return .frozenCard(.beyondSubstrate)
        }
        guard paddedFrameIsExpressible(from: origin, to: destination, config: config) else {
            return .frozenCard(.tallerThanThePlanet)
        }
        return .drawTheFlight
    }

    /// Whether the frame the film would actually ask for — both ends, padded the
    /// way every wide beat is padded — is a region that can exist.
    ///
    /// The same arithmetic `MapKitSnapshotProvider.region` enforces, evaluated
    /// here as pure maths so the film's form is chosen rather than discovered.
    /// **Deliberately duplicated rather than shared**: the provider's copy is a
    /// crash guard that must hold for every frame from every caller, and this one
    /// is a film decision. Collapsing them would make the crash guard skippable.
    static func paddedFrameIsExpressible(
        from origin: RecapCoordinate, to destination: RecapCoordinate, config: TrackingConfig.Export
    ) -> Bool {
        let bounds = CameraPath.Bounds(
            minLat: min(origin.lat, destination.lat), maxLat: max(origin.lat, destination.lat),
            minLon: min(origin.lon, destination.lon), maxLon: max(origin.lon, destination.lon)
        )
        let spanM = CameraPath.fittingSpanM(bounds: bounds, config: config) * config.wideSpanPadding
        let latitudinalM = spanM * Double(config.frameHeightPx) / Double(config.frameWidthPx)
        return latitudinalM / Geo.metersPerDegreeLatitude <= 180
    }

    /// The still frame the title card sits over and the aircraft crosses — both
    /// ends, padded as every other wide beat is.
    ///
    /// One frame for the whole beat is the point: **the camera does not move**, so
    /// the beat costs one snapshot at any distance, and it is the language every
    /// airline route map already speaks. A camera translating thousands of
    /// kilometres is either a very long shot or the 2026-08-02 strobing defect
    /// rebuilt (`Docs/camera-arcs.md` §0).
    public static func flightFrame(
        from origin: RecapCoordinate, to destination: RecapCoordinate, config: TrackingConfig.Export
    ) -> CameraFrame {
        let bounds = CameraPath.Bounds(
            minLat: min(origin.lat, destination.lat), maxLat: max(origin.lat, destination.lat),
            minLon: min(origin.lon, destination.lon), maxLon: max(origin.lon, destination.lon)
        )
        let frame = CameraPath.frame(for: bounds, config: config, padding: config.wideSpanPadding)
        return CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: 0
        )
    }
}
