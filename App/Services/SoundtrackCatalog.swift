import Foundation
import KamomeConfig
import KamomeExportEngine

/// **The music the app carries** (ADR 2026-11-03-the-film-chooses-its-music-and-plays-it-on-silent):
/// `App/Resources/Soundtracks/`, flattened into the bundle — one catalog JSON
/// listing the track ids, and per track its `.m4a` and its manifest, written at
/// the desk by `Tools/kamome-soundtrack-catalog.py`.
///
/// Every manifest is validated on load by the same rules the desk and
/// `./check.sh` apply. One that fails is a build that should never have
/// shipped: it is logged and left out, never played.
struct SoundtrackCatalog {
    let manifests: [SoundtrackManifest]
    private let bundle: Bundle

    init(manifests: [SoundtrackManifest], bundle: Bundle) {
        self.manifests = manifests
        self.bundle = bundle
    }

    static let catalogResource = "SoundtrackCatalog"

    private struct Listing: Decodable {
        let tracks: [String]
    }

    /// The app's own catalog, loaded once.
    @MainActor static func bundled(limits: TrackingConfig.Soundtrack) -> SoundtrackCatalog {
        if let cached { return cached }
        let catalog = load(bundle: .main, limits: limits)
        cached = catalog
        return catalog
    }

    @MainActor private static var cached: SoundtrackCatalog?

    static func load(bundle: Bundle, limits: TrackingConfig.Soundtrack) -> SoundtrackCatalog {
        guard let url = bundle.url(forResource: catalogResource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let listing = try? JSONDecoder().decode(Listing.self, from: data) else {
            KamomeLog.recap.error("music: no soundtrack catalog in the bundle — every film will be silent")
            return SoundtrackCatalog(manifests: [], bundle: bundle)
        }
        let manifests = listing.tracks.compactMap { id -> SoundtrackManifest? in
            do {
                guard let url = bundle.url(forResource: id, withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try SoundtrackManifest.load(from: Data(contentsOf: url), limits: limits)
            } catch {
                // The id names a style, which says where the trip went (§4.4).
                KamomeLog.recap.error("music: a bundled track was refused — \(id, privacy: .private): \(error)")
                return nil
            }
        }
        return SoundtrackCatalog(manifests: manifests, bundle: bundle)
    }

    func manifest(id: String) -> SoundtrackManifest? {
        manifests.first { $0.id == id }
    }

    /// The track's audio beside its manifest.
    func audioURL(for manifest: SoundtrackManifest) -> URL? {
        let file = manifest.file as NSString
        return bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension)
    }
}
