import Foundation

// Outside the class body, which is at SwiftLint's length limit.
extension RecapExportCoordinator {
    /// Whether the run in flight has seen Kamome leave the foreground, and
    /// whether iOS then took its background time back (#260).
    struct LeftApp: Equatable {
        var foreground = false
        var expired = false
    }

    /// **An export that leaving Kamome ended says so** (#260, device run
    /// 2026-10-09). The render cannot draw the map without the GPU, which iOS
    /// does not give an app in the background or behind a locked screen. Two
    /// things then happened, and neither told the user why:
    /// - an app switch let the background assertion expire, which cancelled the
    ///   export as though the user had pressed Cancel, so the screen went back
    ///   to ready with no word;
    /// - a locked screen let a snapshot time out, and the screen showed
    ///   `KamomeExportEngine.SnapshotTimeout · 1`.
    ///
    /// Both now fail with one sentence that names the cause and what to do. The
    /// user's own Cancel stays a cancel, and a film that finished is untouched.
    /// The original failure code is already in the log
    /// (`RecapExportJob+Render.swift`), so nothing a tester needs is lost.
    static func reported(_ outcome: RecapExportOutcome, leftApp: LeftApp) -> RecapExportOutcome {
        let leftAppFailure = RecapExportOutcome.failed(message: String(localized: "recap_failed_left_app"))
        switch outcome {
        case .finished: return outcome
        case .cancelled: return leftApp.expired ? leftAppFailure : outcome
        case .failed: return leftApp.foreground ? leftAppFailure : outcome
        }
    }
}
