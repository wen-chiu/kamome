import Foundation
import KamomeConfig

/// **A database call that fails says so** (arch review 2026-09-24, P1-5).
///
/// App and UI used to call the repository through `try?` in about 35 places
/// against `Arch.md` §5 ("no silent fallbacks"): a stop rename, a film delete or
/// a routing verdict could fail and leave nothing behind but a screen that did
/// not change. These two wrappers keep the call sites as short as `try?` was
/// and add the one thing it dropped — a log line naming what failed.
///
/// `what` is a `StaticString` on purpose: it cannot carry a stop name, a title
/// or a coordinate, so a failure is always loggable in the clear (§0). The error
/// itself stays private in the log.
enum Stored {
    /// A write. Returns whether it landed, for the callers that must not go on
    /// as if it had (deleting a film's file after its row, for one).
    @discardableResult
    static func write(_ what: StaticString, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            return true
        } catch {
            KamomeLog.storage.error("write failed — \(what.description, privacy: .public): \(error)")
            return false
        }
    }

    /// A read. Nil on failure, exactly as `try?` gave — the screen shows what it
    /// shows for "nothing there" — but the failure is no longer invisible.
    static func read<Value>(_ what: StaticString, _ body: () throws -> Value?) -> Value? {
        do {
            return try body()
        } catch {
            KamomeLog.storage.error("read failed — \(what.description, privacy: .public): \(error)")
            return nil
        }
    }
}
