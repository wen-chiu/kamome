import CoreGraphics
import Foundation

/// One of the eight drawn directions a `directional` set covers, at 45° steps
/// clockwise from north. Why eight drawings rather than one rotated image, and
/// what each of them must show, is `Resources/Vehicles/README.md` — the
/// specification for the art and for this loader alike.
public enum SpriteDirection: String, CaseIterable {
    // Raw values are the filenames: `n.png`, `ne.png`, …
    case north = "n"
    case northEast = "ne"
    case east = "e"
    case southEast = "se"
    case south = "s"
    case southWest = "sw"
    case west = "w"
    case northWest = "nw"

    /// Compass bearing this direction is drawn at, degrees clockwise from north.
    public var degrees: Double { Double(Self.allCases.firstIndex(of: self) ?? 0) * 45 }

    /// The bucket a travel bearing falls in — nearest 45°, wrapping at 360°.
    /// No interpolation and no rotation: the sprite either is the right drawing
    /// or it is the neighbouring one, which is the whole point of the technique.
    public static func nearest(toBearing bearing: Double) -> SpriteDirection {
        let wrapped = bearing.truncatingRemainder(dividingBy: 360)
        let positive = wrapped < 0 ? wrapped + 360 : wrapped
        let bucket = Int((positive / 45).rounded()) % allCases.count
        return allCases[bucket]
    }
}

/// Finds this target's resource bundle **without trapping**.
///
/// SwiftPM's generated `Bundle.module` accessor calls `fatalError` when no
/// candidate matches. That made the loader's own `return nil` — and the marker
/// fallback behind it — unreachable for precisely the failure they were written
/// for: it was the only `fatalError` on the shipped export path, and it had been
/// observed firing intermittently (PR #14).
///
/// A candidate is accepted only if it can actually produce the vehicle manifest,
/// so "found a bundle" and "found the artwork" cannot diverge.
public enum VehicleResourceBundle {
    /// Anchors `Bundle(for:)` to whichever binary these sources were linked into.
    private final class Locator {}

    /// `<package>_<target>`: the name SwiftPM gives a target's resource bundle.
    private static let bundleName = "KamomeCore_KamomeExportEngine"

    /// The manifest is the probe: it is the one file the loader cannot work
    /// without, and `.copy` keeps it at a known path inside `Vehicles/`.
    static let manifestResource = (name: "vehicles", ext: "json", subdirectory: "Vehicles")

    public static let resolved: Bundle? = {
        let hosts = [Bundle(for: Locator.self), Bundle.main]
        let nested = hosts.compactMap { host -> Bundle? in
            guard let url = host.resourceURL?.appendingPathComponent("\(bundleName).bundle") else { return nil }
            return Bundle(url: url)
        }
        return (nested + hosts).first {
            $0.url(
                forResource: manifestResource.name,
                withExtension: manifestResource.ext,
                subdirectory: manifestResource.subdirectory
            ) != nil
        }
    }()
}
