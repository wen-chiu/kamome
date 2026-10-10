import Foundation
import KamomeImportKit

/// The scan's work off the main actor, and how its journeys are matched to the
/// hidden ones, and whether a name is still coming. Moved out of the class body
/// when #170 took it past SwiftLint's 250 lines.
extension JourneyDiscoveryModel {
    /// Journeys and each one's cluster plan, from the library's photographs.
    ///
    /// Home is estimated on device to decide what is "away", and that is all
    /// it is used for: the estimate never leaves this function.
    /// Off the main actor: with the country rule a scan is ~0.3 s per 50,000
    /// photographs on a Mac (measured 2026-09-25, release), more on a phone,
    /// and the scanning spinner must keep turning. The outlines are read for
    /// this scan only (≈0.8 MB, released after); nothing loads at launch.
    /// Unreadable → the country rule is off.
    static func detect(
        _ photos: [ImportPhoto], config: JourneyDetectionConfig, clustering: ImportClusteringConfig
    ) async -> (JourneyDetection, [String: ImportedTripPlan]) {
        await Task.detached(priority: .userInitiated) {
            let detection = JourneyDetector.detect(
                photos: photos, config: config, countries: CountryBoundaries.bundled()
            )
            let plans = detection.journeys.map { PhotoImportClusterer.plan(photos: $0.photos, config: clustering) }
            return (detection, Dictionary(zip(detection.journeys.map(\.key), plans)) { first, _ in first })
        }.value
    }

    /// The keys this scan hides: each hidden journey found again by its
    /// photographs, wherever its key has moved (#170) — unless this library's
    /// asset ids do not tell photographs apart, when only the keys count.
    func reconciledHiddenKeys() -> Set<String> {
        guard matchesTripsByPhotographs else { return dismissed.keys }
        return dismissed.reconcile(
            with: detected.mapValues { Set($0.photos.map(\.assetId)) },
            minShare: config.photoImport.duplicatePhotoShare
        )
    }

    /// Whether a journey still has a name coming: what the entry's spinner
    /// shows. False once its lookup has answered nothing, so a journey Apple
    /// cannot name keeps its month title rather than spinning for good (#263).
    func awaitsName(_ summary: JourneySummary) -> Bool {
        summary.name == nil && summary.nameLookupLat != nil && !unanswered.contains(summary.id)
    }
}
