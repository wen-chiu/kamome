import KamomePersistence

/// What made this trip, as the screen says it (§3; ADR 2026-09-28-sample-trip).
extension TripDetailModel {
    /// True for photo-reconstructed trips — drives the S3 provenance note (§3).
    /// False for the sample, which says it is a sample instead.
    var isReconstructed: Bool {
        guard let source = detail?.trip.tripSource else { return false }
        return source.isReconstructed && !source.isSample
    }

    /// Kamome's sample trip, which is nobody's journey.
    var isSample: Bool {
        detail?.trip.tripSource.isSample ?? false
    }
}
