import Foundation

/// **Whether the phone throttled the export** (2026-09-25). An export runs for
/// minutes at full CPU and GPU, and iOS slows a hot phone down. A render that
/// reached `.serious` partway through measures the heat as much as the code,
/// and without this line a slow reading from a hot phone looks like a slow
/// pipeline.
///
/// Records the worst state seen and how long the phone spent at `.serious` or
/// above, from `begin()` to `end()`. The state reader and notification centre
/// are injected so a test can drive it without heating a phone.
final class ThermalWatch: @unchecked Sendable {
    struct Reading: Equatable {
        var start: ProcessInfo.ThermalState
        var worst: ProcessInfo.ThermalState
        var end: ProcessInfo.ThermalState
        var hotS: Double
    }

    private let state: () -> ProcessInfo.ThermalState
    private let center: NotificationCenter
    private let clock: () -> Double
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var start = ProcessInfo.ThermalState.nominal
    private var worst = ProcessInfo.ThermalState.nominal
    private var current = ProcessInfo.ThermalState.nominal
    private var hotSince: Double?
    private var hotS = 0.0

    init(
        state: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        center: NotificationCenter = .default,
        clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.state = state
        self.center = center
        self.clock = clock
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    func begin() {
        lock.lock()
        let now = state()
        start = now
        worst = now
        current = now
        hotS = 0
        hotSince = Self.isHot(now) ? clock() : nil
        lock.unlock()
        observer = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.changed() }
    }

    /// Stops watching and returns the reading.
    func end() -> Reading {
        if let observer { center.removeObserver(observer) }
        observer = nil
        changed()
        lock.lock()
        defer { lock.unlock() }
        if let hotSince { hotS += clock() - hotSince }
        hotSince = nil
        return Reading(start: start, worst: worst, end: current, hotS: hotS)
    }

    private func changed() {
        lock.lock()
        defer { lock.unlock() }
        let now = state()
        current = now
        if now.rawValue > worst.rawValue { worst = now }
        switch (hotSince, Self.isHot(now)) {
        case (nil, true): hotSince = clock()
        case (let since?, false):
            hotS += clock() - since
            hotSince = nil
        default: break
        }
    }

    private static func isHot(_ state: ProcessInfo.ThermalState) -> Bool {
        state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    /// A fixed word for the log, never a formatted value.
    static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
