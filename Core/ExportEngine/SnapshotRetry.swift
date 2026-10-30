import Foundation
import KamomeConfig

/// **A map snapshot that fails is asked again, from the same source, a bounded
/// number of times** (#330, Chiu 2026-10-29).
///
/// Until then one snapshot that timed out or lost its connection failed the
/// whole export: on the simulator, 3 of 72 snapshots failed with a TLS error
/// under load, and 3 min 14 s of render was thrown away; the same export
/// finished on the next try. A road trip is often exported where the signal is
/// weak, so a dropped connection is an ordinary event, not a broken export.
///
/// **Not a fallback** (`CHARTER.md` §4, "fail loudly"): the attempt is the same
/// call to the same renderer with the same style, so a retry that succeeds
/// draws the picture the first attempt would have drawn. When every attempt
/// fails, the last error is thrown and the export fails exactly as before.
/// Every retry is logged with the error's domain and code, never its text,
/// which may carry a tile URL (§0).
///
/// **Two things are never retried:**
/// - a `CancellationError`, which is the export being stopped, not a failure;
/// - any failure once `keepTrying` says no, which is the person pressing
///   Cancel. Cancel is read between frames, and a station that is retrying has
///   no frames, so without this a Cancel would wait out every attempt.
enum SnapshotRetry {
    /// Runs `attempt`; while it throws, waits each of `delaysS` in turn and
    /// runs it again. `onRetry` is called once per retry, before its wait.
    static func run<Value>(
        delaysS: [Double],
        keepTrying: () -> Bool,
        onRetry: () -> Void,
        attempt: () async throws -> Value
    ) async throws -> Value {
        for (index, delay) in delaysS.enumerated() {
            do {
                return try await attempt()
            } catch let cancelled as CancellationError {
                throw cancelled
            } catch {
                guard keepTrying() else { throw error }
                onRetry()
                // Domain and code only: a MapLibre error's text can carry a
                // tile URL, and z/x/y is a place (§0).
                let bridged = error as NSError
                let code = "\(bridged.domain) · \(bridged.code)"
                KamomeLog.recap.notice("snapshot retry \(index + 1) of \(delaysS.count) after \(code, privacy: .public)")
                try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                guard keepTrying() else { throw error }
            }
        }
        return try await attempt()
    }
}
