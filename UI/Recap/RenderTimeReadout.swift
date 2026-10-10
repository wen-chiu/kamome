import Foundation

/// 「算圖耗時 X 秒」 / "Rendered in X s" — a developer's measurement, so it is
/// drawn in Debug builds only (Chiu 2026-10-10, #288: 「Release 隱藏，只留
/// Debug」, reopening 2026-09-26 and ADR 2026-10-02-the-finished-screen-is-
/// the-film). The number is still in the export log in every build. One rule
/// for the finished screen and the film player, so the two cannot drift.
enum RenderTimeReadout {
    /// Whether this build draws the readout.
    static let isShown: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    /// The line to draw, or nil: no time measured, or a Release build.
    static func text(seconds: Double?, shown: Bool = isShown) -> String? {
        guard shown, let seconds else { return nil }
        return String.localizedStringWithFormat(
            String(localized: "recap_render_time"), String(format: "%.1f", seconds)
        )
    }
}
