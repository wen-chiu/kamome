import CoreGraphics
import Foundation
import KamomeConfig

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

    /// Resolved once per process, and **on failure it says what it tried**
    /// (Chiu 2026-08-28).
    ///
    /// This lookup has failed twice in the field and been diagnosed neither
    /// time. Until 2026-08-15 it trapped, and the crash named only the bundle;
    /// since then it returns nil, and on 2026-08-28 a review render drew the
    /// vector marker with a console identical to the three renders beside it.
    /// "Not found" is the answer both incidents already had — *which candidate,
    /// and whether it was on disk*, is the answer neither could give, and it is
    /// the difference between an install-timing fault and a packaging one.
    ///
    /// Failure path only: a process that resolves the bundle logs nothing. The
    /// trace is filesystem paths, never anything derived from a trip, so §0 is
    /// not engaged. It ships rather than being reached for afterwards because
    /// the failure is intermittent — it has to be present when it happens.
    public static let resolved: Bundle? = {
        let outcome = resolve(hosts: [Bundle(for: Locator.self), Bundle.main])
        if outcome.bundle == nil {
            KamomeLog.recap.error("""
                subject: \(bundleName, privacy: .public).bundle did not resolve — \
                \(outcome.trace, privacy: .public)
                """)
        }
        return outcome.bundle
    }()

    /// The candidate walk, kept separate from `resolved` so the failure it
    /// reports can be exercised: `resolved` is a lazily-initialised global with
    /// no seam, and a diagnostic that can never be shown to fire is one nobody
    /// should trust.
    ///
    /// Order is unchanged — every host's nested `<bundleName>.bundle` first, in
    /// host order, then the hosts themselves — and `trace` is empty whenever a
    /// candidate is accepted.
    static func resolve(hosts: [Bundle]) -> (bundle: Bundle?, trace: String) {
        var trace: [String] = []
        var candidates: [Bundle] = []
        for host in hosts {
            guard let url = host.resourceURL?.appendingPathComponent("\(bundleName).bundle") else {
                trace.append("\(host.bundlePath): no resourceURL")
                continue
            }
            guard let nested = Bundle(url: url) else {
                // The one distinction the two incidents needed and neither had:
                // a directory that is absent is a different fault from one that
                // is present and will not open.
                let onDisk = FileManager.default.fileExists(atPath: url.path)
                trace.append("\(url.path): \(onDisk ? "on disk, will not open as a bundle" : "not on disk")")
                continue
            }
            candidates.append(nested)
        }
        let manifest = "\(manifestResource.subdirectory)/\(manifestResource.name).\(manifestResource.ext)"
        for candidate in candidates + hosts {
            if candidate.url(
                forResource: manifestResource.name,
                withExtension: manifestResource.ext,
                subdirectory: manifestResource.subdirectory
            ) != nil {
                return (candidate, "")
            }
            trace.append("\(candidate.bundlePath): opened, no \(manifest)")
        }
        return (nil, trace.joined(separator: " · "))
    }
}
