import Foundation

/// Minimal thread-safe box: the transport closure is @Sendable, so test
/// observation has to be lock-protected.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

extension Locked where Value == Int {
    /// Returns the incremented value.
    @discardableResult
    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
