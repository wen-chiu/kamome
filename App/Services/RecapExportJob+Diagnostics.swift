import BackgroundTasks
import Foundation
import KamomeConfig

/// **What the phone and the map renderer did during a render** (2026-09-25, the
/// 859 s Iceland film). `render cost` says how long snapshots took; these lines
/// say why, and decide which of the next fixes is worth making
/// (`Docs/handoff-export-performance.md` §8). Counts, durations and fixed words
/// only — nothing here names a place (§0).
extension RecapExportJob {
    /// What `beginConditions` started and `reportConditions` reads back.
    struct RenderConditions {
        let thermal: ThermalWatch
        let measuresSubstrate: Bool
    }

    /// Logs the device's state, sizes the map cache and zeroes the substrate
    /// meter — before the first snapshot, which is when MapLibre asks for its
    /// cache size to be set.
    func beginConditions(plan: Plan) async -> RenderConditions {
        let thermal = ThermalWatch()
        thermal.begin()
        KamomeLog.recap.notice("""
            render device: thermal \(ThermalWatch.name(ProcessInfo.processInfo.thermalState), privacy: .public) · \
            low power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off", privacy: .public) · \
            background GPU \(Self.backgroundGPU, privacy: .public)
            """)
        let measuresSubstrate = plan.provider is MapLibreSnapshotProvider
        if measuresSubstrate {
            let cacheMb = plan.config.pipeline.mapCacheMb
            if let error = await MapLibreSnapshotProvider.prepareForExport(cacheMb: cacheMb) {
                // Not fatal: the render still works on the old cache size, only
                // slower if it evicts. Full text private, as for a failed export.
                KamomeLog.recap.error("map cache: could not set \(cacheMb) MB — \(error)")
            } else {
                KamomeLog.recap.notice("map cache: \(cacheMb) MB ambient")
            }
        }
        return RenderConditions(thermal: thermal, measuresSubstrate: measuresSubstrate)
    }

    /// **Why the snapshots cost what they did**, logged on every exit —
    /// finished, cancelled or failed — because an abandoned slow export is still
    /// a reading (`MapSubstrateMeter`, `ThermalWatch`).
    ///
    /// How to read `render substrate`:
    /// - `style` against `mean`: the share of each snapshot spent before its
    ///   style had loaded, which a persistent renderer would pay once. "n/a"
    ///   means MapLibre never reported a style load.
    /// - `refetched`: tiles downloaded a second time because the cache had
    ///   dropped them. Many of these mean `map_cache_mb` is too small;
    ///   `revalidated` repeats are expired tiles checked, not re-downloaded.
    /// - `peak in flight` 1 means snapshots never overlapped, and
    ///   `prefetch_depth` bought no concurrency.
    func reportConditions(_ conditions: RenderConditions) {
        let thermal = conditions.thermal.end()
        KamomeLog.recap.notice("""
            render thermal: \(ThermalWatch.name(thermal.start), privacy: .public) → \
            \(ThermalWatch.name(thermal.end), privacy: .public) · \
            worst \(ThermalWatch.name(thermal.worst), privacy: .public) · \
            \(thermal.hotS, format: .fixed(precision: 0))s at serious or above
            """)
        guard conditions.measuresSubstrate else { return }
        let map = MapLibreSnapshotProvider.meter.read()
        let style = map.meanStyleS.map { String(format: "%.2fs", $0) } ?? "n/a"
        KamomeLog.recap.notice("""
            render substrate: \(map.snapshots) snapshots (\(map.failedSnapshots) failed) · \
            mean \(map.meanSnapshotS, format: .fixed(precision: 2))s, style \(style, privacy: .public) · \
            peak in flight \(map.peakInFlight) · \
            requests \(map.requests) / \(map.distinctRequests) distinct · \
            \(map.revalidations) revalidated · \(map.refetches) refetched
            """)
    }

    /// Whether this phone could keep rendering the map with the app in the
    /// background (iOS 26 continued-processing tasks with GPU). Logged, not
    /// used: it decides whether that option is worth building at all.
    private static var backgroundGPU: String {
        if #available(iOS 26.0, *) {
            return BGTaskScheduler.supportedResources.contains(.gpu) ? "supported" : "not supported"
        }
        return "n/a (iOS < 26)"
    }
}
