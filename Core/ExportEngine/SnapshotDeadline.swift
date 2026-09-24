import Foundation

/// **A map snapshot that never answers ends the export instead of holding it**
/// (arch review 2026-09-24, P1-10).
///
/// The render waits on each station's snapshot, and Cancel is read between
/// frames — so a snapshot whose completion never fires held the export, and
/// Cancel with it, for as long as the process lived. `export.pipeline.
/// snapshot_timeout_s` bounds that wait for any substrate.
///
/// **Not a task group, on purpose.** A group waits for every child before it
/// returns, and a snapshot bridged from a callback does not stop when
/// cancelled, so a group-based race would still wait for the stuck one. Here
/// whichever finishes first — the work or the deadline — resumes the caller; the
/// loser is cancelled and its late answer is dropped.
public struct SnapshotTimeout: Error, CustomStringConvertible {
    public let seconds: Double
    public var description: String { "map snapshot did not complete within \(seconds) s" }
}

enum SnapshotDeadline {
    static func run<Value>(
        seconds: Double, _ work: @escaping () async throws -> Value
    ) async throws -> Value {
        let gate = Gate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.arm(continuation)
                let worker = Task {
                    do { gate.finish(.success(try await work())) } catch { gate.finish(.failure(error)) }
                }
                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    gate.finish(.failure(SnapshotTimeout(seconds: seconds)))
                }
                // Whoever won, the other is no longer wanted: a late snapshot is
                // dropped, a pending timer never fires.
                gate.onFinish {
                    timer.cancel()
                    worker.cancel()
                }
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }

    /// Resumes the continuation exactly once, whoever gets there first.
    private final class Gate<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Error>?
        private var pending: Result<Value, Error>?
        private var done = false
        private var finished: (() -> Void)?

        func arm(_ continuation: CheckedContinuation<Value, Error>) {
            lock.lock()
            if let pending {
                lock.unlock()
                continuation.resume(with: pending)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func onFinish(_ action: @escaping () -> Void) {
            lock.lock()
            if done {
                lock.unlock()
                action()
                return
            }
            finished = action
            lock.unlock()
        }

        /// True for the call that decided the outcome.
        @discardableResult
        func finish(_ result: Result<Value, Error>) -> Bool {
            lock.lock()
            guard !done else {
                lock.unlock()
                return false
            }
            done = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil { pending = result }
            let action = finished
            finished = nil
            lock.unlock()
            continuation?.resume(with: result)
            action?()
            return true
        }
    }
}
