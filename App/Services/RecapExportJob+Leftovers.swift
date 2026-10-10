import Foundation
import KamomeConfig

/// Render files a killed export left in tmp (#279). Its own file because
/// `RecapExportJob+Render.swift` is at its length limit.
extension RecapExportJob {
    /// What every render's file in tmp is called before it moves to `Films/`.
    nonisolated static let renderFilePrefix = "kamome-recap-"

    /// **A render a killed process left in tmp goes before the next one starts**
    /// (#279). Cancel and failure delete their own file (`cleanup`), but a
    /// render ended by jetsam, a crash or the app being swiped away leaves tens
    /// of MB nothing would remove until iOS purges tmp. One export runs at a
    /// time, app-wide (`RecapExportCoordinator`), so any render file already
    /// there when one starts is a leftover. Returns how many were removed.
    @discardableResult
    nonisolated static func sweepLeftoverRenders(in directory: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let leftovers = files.filter { $0.lastPathComponent.hasPrefix(renderFilePrefix) }
        let removed = leftovers.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
        if removed > 0 {
            KamomeLog.recap.notice("export: removed \(removed, privacy: .public) render files a killed export left in tmp")
        }
        return removed
    }
}
