import Foundation

/// **A Bool set on the main actor and read from a worker that cannot hop to
/// it** — the render loop between frames, routing between legs, photo analysis
/// between photographs.
///
/// There used to be three copies of this class, one per coordinator
/// (`ExportCancelFlag`, and a private `CancelFlag` in `RouteMatchCoordinator`
/// and in `PhotoAnalysisCoordinator`), identical line for line (arch review
/// 2026-09-26, round 2 point 6). One type, so a fix to one is a fix to all.
final class SharedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    func clear() { lock.withLock { value = false } }
    var isSet: Bool { lock.withLock { value } }
}
