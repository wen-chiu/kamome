import Foundation
import GRDB

/// **What routing established about a trip's segments** (schema v4, 2026-08-30).
///
/// Its own file rather than another method on `TripRepository`, which is at its
/// length budget — and the split is a real seam rather than a lint dodge: every
/// other writer on that type is import-time or user-edit, while this one is
/// written by a **detached background step** that may run long after the trip was
/// saved and long before the film is rendered.
public extension TripRepository {
    /// Stores what routing **established** about one segment's routability
    /// (schema v4). Separate from `setMatchedPolyline` on purpose: a verdict of
    /// "there is no road here" has no geometry to store, and it is precisely that
    /// case the crossing beat is built on, so it cannot ride along on the
    /// polyline write.
    ///
    /// Never writes NULL. NULL means "nobody found out", and a run that learnt
    /// something must not be able to un-learn it for a later run — the same
    /// one-way property that makes `setMatchedPolyline` safe against two
    /// concurrent routing runs.
    func setRoutability(segmentId: String, _ verdict: SegmentRoutability) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE segment SET routability = ? WHERE id = ?",
                arguments: [verdict.rawValue, segmentId]
            )
        }
    }
}
