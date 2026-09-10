import Foundation
import KamomeConfig
import KamomePersistence

/// File-level operations for stored recap films.
///
/// Films live in `Application Support/Films/`. The database stores a path
/// **relative** to Application Support so the reference survives the container
/// UUID change that happens on every app update and restore. This service is
/// the only place that resolves the relative path back to an absolute URL.
///
/// The Persistence module stays file-system-unaware — it stores and returns
/// `FilmRecord.relativePath`; this service owns the mapping between that
/// string and the file on disk.
enum FilmStore {
    /// The subdirectory name under Application Support.
    static let directoryName = "Films"

    // MARK: - Directory

    /// The `Application Support/Films/` directory, created if absent.
    static func filmsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Application Support root — the base all relative paths are resolved
    /// against. Separated from `filmsDirectory()` so the resolver does not
    /// silently create the Films subdirectory on every read.
    static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    // MARK: - File operations

    /// Moves a rendered file from tmp into the Films directory. Returns the
    /// relative path that `FilmRecord.relativePath` should store.
    ///
    /// **Move, not copy** — the rendered file is the size of a film (tens of
    /// MB), and the tmp original is about to be purged anyway.
    static func moveToStore(from tempURL: URL) throws -> String {
        let dir = try filmsDirectory()
        let destination = dir.appendingPathComponent(tempURL.lastPathComponent)
        // If a previous export left a file with the same timestamp name
        // (highly unlikely but not impossible), remove it first.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return "\(directoryName)/\(tempURL.lastPathComponent)"
    }

    /// Resolves a stored relative path to an absolute URL. Returns nil when
    /// the Application Support directory cannot be located (should not happen
    /// on a running device, but the caller should not crash on it).
    static func resolvedURL(relativePath: String) -> URL? {
        guard let support = try? applicationSupportDirectory() else { return nil }
        return support.appendingPathComponent(relativePath)
    }

    /// Resolves a relative path against an **arbitrary** base — the test seam
    /// that proves the app-update scenario. The production caller passes
    /// `applicationSupportDirectory()`; the test passes a different root.
    static func resolvedURL(relativePath: String, base: URL) -> URL {
        base.appendingPathComponent(relativePath)
    }

    /// Deletes the file for a film record. Best-effort — the file may have
    /// already been removed by the system, and that is not an error.
    static func deleteFile(relativePath: String) {
        guard let url = resolvedURL(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes files for a batch of film records (the trip-deletion cascade).
    static func deleteFiles(films: [FilmRecord]) {
        for film in films {
            deleteFile(relativePath: film.relativePath)
        }
    }

    /// File size in bytes, or nil when the file is not readable.
    static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64
        else { return nil }
        return size
    }
}
