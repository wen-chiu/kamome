import Foundation
import ImageIO
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import Photos
import UIKit
import Vision

/// The analyser's version, stored on every row. Bump it when what a row means
/// changes — a new request, a new revision — and every photograph is analysed
/// again.
///
/// **2** (handoff-music §2.4) added scene labels and colour for the film's
/// music. Its pick signals — utility, quality, feature print — are version 1's
/// unchanged, so a version-1 row still serves the photo pick (`pickSignals`)
/// while it waits to be analysed again; only its mood reads as neutral.
enum PhotoAnalysisVersion {
    static let current = 2
    /// The oldest version whose utility, quality and feature print the photo
    /// pick may use. Raise it only when one of those three changes.
    static let pickSignals = 1
    /// The oldest version that measured mood.
    static let mood = 2
}

/// **Vision looks at one photograph, on the device** (ADR 2026-09-25 (d)).
///
/// Three facts per photograph, each the cheapest request that gives it:
///  - *utility* — `PHAsset.mediaSubtypes` says screenshot without any pixels;
///    from iOS 18, `VNCalculateImageAestheticsScoresRequest.isUtility` catches
///    receipts and documents taken with the camera.
///  - *quality* — the same request's `overallScore`, iOS 18 only. On iOS 17 it
///    stays NULL and each slot takes the photograph at its centre, as before.
///  - *feature print* — `VNGenerateImageFeaturePrintRequest`, pinned to revision
///    2 (iOS 17) so every device's prints share one space.
///  - *mood* (version 2) — `VNClassifyImageRequest`'s labels from a fixed
///    whitelist (`PhotoMood.Label`), kept at `label_confidence_min`, and mean
///    luminance, saturation and warmth of a `mood_sample_px` square
///    downsample of the same pixels. For the film's music only (§2.4).
///
/// Pixels come from `PhotoKitImageLoader` at `photo_analysis.target_px` and are
/// dropped when the function returns; nothing is written but the row, and
/// nothing leaves the device (§0).
enum PhotoAnalyzer {
    /// Where the pixels came from — the probe's question about iCloud.
    enum Source: String, CaseIterable {
        /// The full-quality image was on the device.
        case local
        /// Only the device's own thumbnail was: iCloud holds the original.
        case thumbnail
        /// Downloaded from iCloud (`allow_network` on).
        case network
        /// No pixels at all.
        case none
    }

    /// One photograph's result and what it cost, in milliseconds.
    struct Result {
        var record: PhotoAnalysisRecord
        var source: Source
        var fetchMs: Double
        var featurePrintMs: Double?
        var aestheticsMs: Double?
        var classifyMs: Double?
    }

    static func analyze(asset: PHAsset?, assetId: String, config: TrackingConfig.PhotoAnalysis) async -> Result {
        let now = Date().timeIntervalSince1970
        guard let asset else {
            let record = PhotoAnalysisRecord(
                phAssetId: assetId, version: PhotoAnalysisVersion.current, outcome: .unavailable, analyzedAt: now
            )
            return Result(record: record, source: .none, fetchMs: 0)
        }
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let clock = ContinuousClock()
        let fetchStart = clock.now
        let (image, source) = await pixels(for: asset, config: config)
        let fetchMs = milliseconds(clock.now - fetchStart)

        guard let cgImage = image?.cgImage else {
            let record = PhotoAnalysisRecord(
                phAssetId: assetId, version: PhotoAnalysisVersion.current, outcome: .unavailable,
                isUtility: isScreenshot ? 1 : nil, analyzedAt: now
            )
            return Result(record: record, source: .none, fetchMs: fetchMs)
        }
        let orientation = CGImagePropertyOrientation(image?.imageOrientation ?? .up)

        let printStart = clock.now
        let featurePrint = self.featurePrint(cgImage, orientation: orientation)
        let featurePrintMs = milliseconds(clock.now - printStart)

        var aesthetics: (score: Double, isUtility: Bool)?
        var aestheticsMs: Double?
        if #available(iOS 18.0, *) {
            let start = clock.now
            aesthetics = self.aesthetics(cgImage, orientation: orientation)
            aestheticsMs = milliseconds(clock.now - start)
        }

        let classifyStart = clock.now
        let labels = sceneLabels(cgImage, orientation: orientation, confidenceMin: config.labelConfidenceMin)
        let classifyMs = milliseconds(clock.now - classifyStart)
        let colour = self.colour(cgImage, side: config.moodSamplePx)

        let isUtility: Int? = if isScreenshot { 1 } else { aesthetics.map { $0.isUtility ? 1 : 0 } }
        let record = PhotoAnalysisRecord(
            phAssetId: assetId, version: PhotoAnalysisVersion.current, outcome: .analyzed,
            isUtility: isUtility, quality: aesthetics?.score,
            featurePrint: featurePrint.map(PhotoAnalysisRecord.encode(featurePrint:)),
            sceneLabels: labels.map { PhotoMood.Label.mask($0) },
            luminance: colour?.luminance, saturation: colour?.saturation, warmth: colour?.warmth, analyzedAt: now
        )
        return Result(
            record: record, source: source, fetchMs: fetchMs,
            featurePrintMs: featurePrint == nil ? nil : featurePrintMs, aestheticsMs: aestheticsMs,
            classifyMs: labels == nil ? nil : classifyMs
        )
    }

    /// The full-quality derivative if the device has it; else, with
    /// `allow_network`, the same downloaded from iCloud; else the device's own
    /// thumbnail, which Photos keeps for every photograph whose original is
    /// in iCloud. Asked in that order so the probe can tell the three apart.
    private static func pixels(
        for asset: PHAsset, config: TrackingConfig.PhotoAnalysis
    ) async -> (UIImage?, Source) {
        func fetch(_ profile: PhotoKitImageLoader.Profile, network: Bool) async -> PhotoFetch {
            await PhotoKitImageLoader.image(for: asset, targetPx: config.targetPx, profile: profile, allowNetwork: network)
        }
        switch await fetch(.deck, network: false) {
        case let .loaded(image): return (image, .local)
        case .cancelled: return (nil, .none)
        case .inCloud, .failed: break
        }
        if config.allowNetwork, case let .loaded(image) = await fetch(.deck, network: true) {
            return (image, .network)
        }
        if case let .loaded(image) = await fetch(.preview, network: false) {
            return (image, .thumbnail)
        }
        return (nil, .none)
    }

    private static func featurePrint(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        do {
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        } catch {
            KamomeLog.importing.error("photo analysis: feature print failed: \(error.localizedDescription)")
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let data = observation.data
        switch observation.elementType {
        case .float:
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .double:
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).map(Float.init) }
        default:
            return nil
        }
    }

    @available(iOS 18.0, *)
    private static func aesthetics(
        _ image: CGImage, orientation: CGImagePropertyOrientation
    ) -> (score: Double, isUtility: Bool)? {
        let request = VNCalculateImageAestheticsScoresRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        } catch {
            // The simulator refuses this request; a device should not.
            KamomeLog.importing.error("photo analysis: aesthetics failed: \(error.localizedDescription)")
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return (Double(observation.overallScore), observation.isUtility)
    }

    /// The whitelisted labels Vision gives at `confidenceMin` or over; nil when
    /// the request failed (an empty set is an answer: none of ours).
    private static func sceneLabels(
        _ image: CGImage, orientation: CGImagePropertyOrientation, confidenceMin: Double
    ) -> [PhotoMood.Label]? {
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        } catch {
            KamomeLog.importing.error("photo analysis: classification failed: \(error.localizedDescription)")
            return nil
        }
        return (request.results ?? []).compactMap { observation in
            Double(observation.confidence) >= confidenceMin ? PhotoMood.Label(rawValue: observation.identifier) : nil
        }
    }

    /// Luminance, saturation and warmth of the image drawn into a `side` ×
    /// `side` sRGB square — no Vision needed (§2.4).
    private static func colour(_ image: CGImage, side: Int) -> PhotoMood.Colour? {
        guard side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? PhotoMood.colour(rgba: pixels) : nil
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
