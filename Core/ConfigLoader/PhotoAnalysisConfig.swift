import Foundation

extension TrackingConfig {
    /// **The app looks at the photographs before it picks them** (ADR
    /// 2026-09-25 (d)). On-device Vision only: pixels and results never leave
    /// the phone (§0). Every value is a first guess, **INFERRED**, until the
    /// Trip Detail probe (DEBUG) is run on a device — see
    /// `Docs/handoff-photo-analysis.md`.
    public struct PhotoAnalysis: Decodable, Equatable {
        /// Longest side, in pixels, of the image Vision is shown. **INFERRED**:
        /// both requests scale their input down to a few hundred pixels, so a
        /// larger derivative buys decode time and nothing else. Not measured.
        public let targetPx: Int
        /// Whether background analysis may download a photograph from iCloud.
        /// **Off**: analysis runs unasked, and downloading a trip's worth of
        /// originals on cellular is not something the person agreed to. A
        /// photograph with only a cloud copy is analysed from the thumbnail the
        /// device keeps, or not at all, and then plays as it always did.
        public private(set) var allowNetwork: Bool
        /// Feature-print distance at or under which two photographs are one
        /// moment (a burst, the same view). **INFERRED** 0.3.
        /// `VNGenerateImageFeaturePrintRequestRevision2` prints are 768 floats of
        /// unit length (VERIFIED on a Mac, 2026-09-25), so distances run 0…2; on
        /// synthetic images a scene nudged 8 px measured 0.07 and two different
        /// scenes 0.45. Set low on purpose: too low and a burst survives (the old
        /// behaviour), too high and two different views collapse into one. The
        /// probe's consecutive-distance histogram on a real trip settles it.
        public let duplicateDistance: Double

        /// The same block with iCloud allowed or not — the DEBUG probe measures
        /// both; the background run only ever uses the file's value.
        public func withNetwork(_ allowed: Bool) -> PhotoAnalysis {
            var copy = self
            copy.allowNetwork = allowed
            return copy
        }

        enum CodingKeys: String, CodingKey {
            case targetPx = "target_px"
            case allowNetwork = "allow_network"
            case duplicateDistance = "duplicate_distance"
        }
    }
}
