import Foundation

/// Reads a desk-harness environment variable, treating **empty as unset**.
///
/// Why this exists (2026-08-15). The scheme now declares every harness variable
/// as `$(TEST_RUNNER_<VAR>)` so that `TEST_RUNNER_<VAR>=…` on the `xcodebuild`
/// command line actually reaches the test process. The cost of that mechanism is
/// that an *unset* variable arrives as a defined empty string rather than as
/// nothing at all — and `if let override = environment["KAMOME_RENDER_OUT"]`
/// then succeeds with "", writing renders to the filesystem root.
///
/// Empty has never meant anything to any harness here, so collapsing it to nil
/// is the reading that was always intended.
enum HarnessEnv {
    static func value(_ name: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[name], !raw.isEmpty else { return nil }
        return raw
    }
}

/// A desk-harness variable was set to something the harness cannot use.
///
/// Refusing beats defaulting: a review render is judged by looking, and a film
/// that quietly ignored the setting the reviewer asked for looks exactly like a
/// film that honoured it. `HarnessEnv.value` already collapses empty to nil, so
/// reaching this means a real value was typed and misread.
struct HarnessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}
