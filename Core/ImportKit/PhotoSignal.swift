import Foundation

/// What on-device analysis learned about one photograph (ADR 2026-09-25 (d)).
/// Read from the database, never computed here: this module stays pure, so the
/// same stored analysis always picks the same deck.
public struct PhotoSignal: Equatable, Sendable {
    /// A screenshot, a receipt, a document — a photograph taken to keep
    /// information, not a moment. Never picked by the app; still shown when
    /// the person starred or picked it.
    public var isUtility: Bool
    /// How good a photograph Vision judges it, higher is better. `nil` where
    /// the device cannot say (iOS 17) or the pixels were not on the device.
    public var quality: Double?
    /// Vision's feature print, for telling a burst from a new view. `nil`
    /// when the pixels were not on the device.
    public var featurePrint: [Float]?

    public init(isUtility: Bool = false, quality: Double? = nil, featurePrint: [Float]? = nil) {
        self.isUtility = isUtility
        self.quality = quality
        self.featurePrint = featurePrint
    }

    /// Euclidean distance between two feature prints, or `nil` when either is
    /// missing or they are not the same length (two Vision revisions).
    public static func distance(_ lhs: [Float]?, _ rhs: [Float]?) -> Double? {
        guard let lhs, let rhs, lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var sum = 0.0
        for index in lhs.indices {
            let delta = Double(lhs[index]) - Double(rhs[index])
            sum += delta * delta
        }
        return sum.squareRoot()
    }

    /// Whether two photographs show the same moment: close enough in Vision's
    /// feature space. Unknown is never a duplicate.
    public static func isDuplicate(_ lhs: PhotoSignal?, _ rhs: PhotoSignal?, within threshold: Double) -> Bool {
        guard let distance = distance(lhs?.featurePrint, rhs?.featurePrint) else { return false }
        return distance <= threshold
    }
}
