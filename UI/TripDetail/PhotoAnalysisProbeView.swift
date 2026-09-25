#if DEBUG
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import Photos
import SwiftUI

/// **The device measurement ADR 2026-09-25 (c) is waiting on** — DEBUG only,
/// from Trip Detail's overflow menu. ⚠️ Needs the physical device: the
/// simulator has no trip's photographs and refuses the aesthetics request.
///
/// Runs the real analyser over every photograph at one of the trip's stops,
/// timing each step, and writes the rows exactly as the background run would —
/// so afterwards the second half of the screen shows the film's decks both
/// ways: by time (what shipped before) and analysed (what ships now).
///
/// Everything reported is a count, a duration or a score. No asset id, name or
/// coordinate reaches the log (§0); the screen itself shows the photographs,
/// which never leave the device.
struct PhotoAnalysisProbeView: View {
    let tripId: String
    let repository: TripRepository
    let config: TrackingConfig

    @State private var report: Report?
    @State private var progress: (done: Int, total: Int)?
    @State private var comparison: [StopComparison] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { measure(allowNetwork: false) } label: { Text(verbatim: "Measure — on device only") }
                    Button { measure(allowNetwork: true) } label: { Text(verbatim: "Measure — allow iCloud") }
                    if let progress { Text(verbatim: "\(progress.done) / \(progress.total)") }
                } footer: {
                    Text(verbatim: "Re-analyses every photograph at a stop and stores the result.")
                }
                if let report {
                    Section { ForEach(report.lines, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()) } }
                }
                ForEach(comparison) { stop in
                    Section { comparisonRows(stop) } header: { Text(verbatim: stop.name) }
                }
            }
            .navigationTitle(Text(verbatim: "Photo analysis probe"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: compare)
        }
    }

    @ViewBuilder
    private func comparisonRows(_ stop: StopComparison) -> some View {
        ForEach([("time", stop.before), ("analysed", stop.after)], id: \.0) { label, deck in
            HStack(spacing: 4) {
                Text(verbatim: label).font(.caption2).frame(width: 52, alignment: .leading)
                ForEach(deck, id: \.self) { assetId in
                    PhotoThumbnail(assetId: assetId, targetPx: 180)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    // MARK: - Measuring

    private func measure(allowNetwork: Bool) {
        let assetIds = (Stored.read("detail") { try repository.detail(tripId: tripId) }?.photos ?? [])
            .filter { $0.stopId != nil }
            .sorted { ($0.takenAt ?? 0, $0.phAssetId) < ($1.takenAt ?? 0, $1.phAssetId) }
            .map(\.phAssetId)
        let analysis = config.photoAnalysis.withNetwork(allowNetwork)
        progress = (0, assetIds.count)
        Task {
            let started = ContinuousClock.now
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
            var assets: [String: PHAsset] = [:]
            fetched.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }
            var results: [PhotoAnalyzer.Result] = []
            for assetId in assetIds {
                let result = await Task.detached(priority: .userInitiated) {
                    await PhotoAnalyzer.analyze(asset: assets[assetId], assetId: assetId, config: analysis)
                }.value
                Stored.write("savePhotoAnalysis") { try repository.savePhotoAnalysis(result.record) }
                results.append(result)
                progress = (results.count, assetIds.count)
            }
            let wall = ContinuousClock.now - started
            let report = Report(results: results, wallS: Double(wall.components.seconds), allowNetwork: allowNetwork)
            self.report = report
            // Numbers only (§0).
            KamomeLog.importing.notice("photo-probe: \(report.lines.joined(separator: " | "), privacy: .public)")
            progress = nil
            compare()
        }
    }

    // MARK: - Before and after

    struct StopComparison: Identifiable {
        let id: String
        let name: String
        let before: [String]
        let after: [String]
    }

    private func compare() {
        guard let detail = Stored.read("detail", { try repository.detail(tripId: tripId) }) else { return }
        let before = RecapComposer.filmPlan(detail: detail, config: config, useAnalysis: false)
        let after = RecapComposer.filmPlan(detail: detail, config: config)
        comparison = after.stops.compactMap { stop in
            let old = before.decks[stop.id], new = after.decks[stop.id]
            guard old != nil || new != nil else { return nil }
            return StopComparison(
                id: stop.id, name: (stop.name ?? "—") + (old == new ? "  · same" : ""),
                before: old ?? [], after: new ?? []
            )
        }
    }
}

/// What the probe measured, as the lines it shows and logs.
private struct Report {
    let lines: [String]

    init(results: [PhotoAnalyzer.Result], wallS: Double, allowNetwork: Bool) {
        var lines = ["photos \(results.count) · wall \(Int(wallS)) s · iCloud \(allowNetwork ? "allowed" : "off") · p50 / p90 / max"]
        for source in PhotoAnalyzer.Source.allCases {
            let fetches = results.filter { $0.source == source }.map(\.fetchMs)
            guard !fetches.isEmpty else { continue }
            lines.append("\(source.rawValue) \(fetches.count) · fetch ms \(Self.spread(fetches))")
        }
        let prints = results.compactMap(\.featurePrintMs)
        lines.append("feature print ms \(prints.isEmpty ? "—" : Self.spread(prints))")
        let aesthetics = results.compactMap(\.aestheticsMs)
        lines.append("aesthetics ms \(aesthetics.isEmpty ? "— (iOS 17 or refused)" : Self.spread(aesthetics))")
        let scores = results.compactMap(\.record.quality)
        lines.append("score \(scores.isEmpty ? "—" : Self.spread(scores, digits: 2))")
        let utility = results.filter { $0.record.isUtility == 1 }.count
        lines.append("utility \(utility) of \(results.count)")
        // Distances between consecutive photographs: where the burst threshold
        // (`photo_analysis.duplicate_distance`) should sit.
        let stored = results.map(\.record.featurePrintFloats)
        let distances = zip(stored, stored.dropFirst()).compactMap { PhotoSignal.distance($0, $1) }
        let edges = [0.2, 0.4, 0.6, 0.8, 1.0]
        var counts = [Int](repeating: 0, count: edges.count + 1)
        for distance in distances { counts[edges.firstIndex { distance <= $0 } ?? edges.count] += 1 }
        let labels = edges.map { "≤\($0)" } + [">1.0"]
        lines.append("consecutive distance " + zip(labels, counts).map { "\($0):\($1)" }.joined(separator: " "))
        self.lines = lines
    }

    /// p50 / p90 / max.
    private static func spread(_ values: [Double], digits: Int = 0) -> String {
        let sorted = values.sorted()
        func at(_ quantile: Double) -> Double { sorted[Int(Double(sorted.count - 1) * quantile)] }
        let format = "%.\(digits)f"
        return [0.5, 0.9, 1.0].map { String(format: format, at($0)) }.joined(separator: " / ")
    }
}
#endif
