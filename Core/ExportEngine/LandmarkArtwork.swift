import CoreGraphics
import Foundation
import ImageIO
import KamomeConfig

/// **The artwork Kamome draws *on* the map, as opposed to *across* it** — today
/// the mark on each end of a type-2 film's crossing (Chiu 2026-09-04, ADR
/// 2026-09-04).
///
/// Its own resource directory and its own loader, separate from
/// `VehicleCatalog`, for a reason that is not tidiness:
///
/// - **It is not a subject.** It is absent from `vehicles.json`, it is not
///   selectable, and no path can draw it as the moving subject. A landmark that
///   lived in `Vehicles/` would be one manifest edit away from being offered to a
///   user as something to drive.
/// - **It must be replaceable on its own.** `Landmarks/flight-end.png` is a
///   **copy** of the seagull sprite today and is a placeholder (Chiu: *先用這個圖,
///   之後會再改*). Sharing the file would mean redrawing the landmark silently
///   restyles the subject, and the reverse.
///
/// `Resources/Landmarks/README.md` carries the four-gull table — this is the
/// fourth distinct gull object in the project, and the three it is not.
///
/// **Decoded once per process**, like `VehicleCatalog`'s sprites: a film asks for
/// this on every frame of its opening.
public enum LandmarkArtwork {
    /// The mark drawn on each end of a crossing, or nil when the artwork could
    /// not be loaded.
    ///
    /// 🔴 **nil is never drawn as nothing.** The caller falls back to the vector
    /// `VehicleMarker.seagull` and says so in the log — see `drawFlightEnds`.
    /// This project has been bitten once by artwork that failed in silence
    /// (`Docs/handoff-subject-lookup.md`, where a missing sprite degraded a film
    /// for two weeks) and once by a defaulted `nil` in `FrameCompositor` that
    /// rendered a different film for a round (2026-09-04). Neither was found by
    /// looking.
    public static var flightEnd: CGImage? { store.image }

    private static let store = Store()

    private final class Store {
        let image: CGImage?

        init() {
            image = Self.decode()
        }

        /// Logs **only on failure**, once, naming what it looked for — the same
        /// shape `VehicleResourceBundle` settled on after two undiagnosed field
        /// failures. A filesystem path is not trip data, so §0 is not engaged.
        private static func decode() -> CGImage? {
            guard let bundle = VehicleResourceBundle.resolved else {
                KamomeLog.recap.error("""
                    landmark artwork: the export engine's resource bundle did not resolve, \
                    so flight-end marks fall back to the vector gull
                    """)
                return nil
            }
            guard let url = bundle.url(
                forResource: "flight-end", withExtension: "png", subdirectory: "Landmarks"
            ) else {
                KamomeLog.recap.error("""
                    landmark artwork: Landmarks/flight-end.png is not in the bundle at \
                    \(bundle.bundlePath) — flight-end marks fall back to the vector gull
                    """)
                return nil
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                KamomeLog.recap.error("""
                    landmark artwork: Landmarks/flight-end.png is present but did not decode \
                    — flight-end marks fall back to the vector gull
                    """)
                return nil
            }
            return decoded
        }
    }
}
