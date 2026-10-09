import Darwin
import Foundation

/// **How close the export came to being killed for memory** (#161). An export
/// holds up to `prefetch_depth` map snapshotters, `composite_concurrency` frames
/// and every deck photo at once, and iOS ends an app that grows too large
/// (jetsam) without a crash report. Without this line a TestFlight export can
/// only say it survived, never by how much — Xcode was the only gauge.
///
/// Records the largest `phys_footprint` seen (the number jetsam judges) and the
/// smallest `os_proc_available_memory()` (how much more the app could have
/// taken), from `begin()` to `end()`. Sampled by the caller on the render's
/// existing ~10/s progress throttle, so it costs one syscall per tick. Counts
/// only — nothing here names a place (§0).
///
/// The reader is injected so a test can drive it without a large render.
final class MemoryWatch: @unchecked Sendable {
    struct Sample: Equatable {
        /// Bytes this process holds, as jetsam counts them.
        var footprint: UInt64
        /// Bytes the process may still take before its limit; 0 where the
        /// platform does not say (the simulator, the Mac).
        var available: UInt64
    }

    struct Reading: Equatable {
        var peakFootprint: UInt64
        /// nil where the platform never reported a limit.
        var lowestAvailable: UInt64?
        var samples: Int
    }

    private let read: () -> Sample?
    private let lock = NSLock()
    private var peakFootprint: UInt64 = 0
    private var lowestAvailable: UInt64?
    private var samples = 0

    init(read: @escaping () -> Sample? = MemoryWatch.current) {
        self.read = read
    }

    func begin() {
        lock.withLock {
            peakFootprint = 0
            lowestAvailable = nil
            samples = 0
        }
        sample()
    }

    /// One reading. Safe from any thread — the render thread calls it.
    func sample() {
        guard let now = read() else { return }
        lock.withLock {
            samples += 1
            peakFootprint = max(peakFootprint, now.footprint)
            if now.available > 0 {
                lowestAvailable = min(lowestAvailable ?? now.available, now.available)
            }
        }
    }

    /// Takes a last reading and returns what was seen.
    func end() -> Reading {
        sample()
        return lock.withLock {
            Reading(peakFootprint: peakFootprint, lowestAvailable: lowestAvailable, samples: samples)
        }
    }

    /// The process's footprint (`TASK_VM_INFO`) and remaining allowance. nil if
    /// the kernel refuses the call, which leaves the reading unchanged.
    static func current() -> Sample? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Sample(footprint: info.phys_footprint, available: UInt64(os_proc_available_memory()))
    }

    /// Whole megabytes for the log line.
    static func megabytes(_ bytes: UInt64) -> Int {
        Int(bytes / 1_048_576)
    }
}
