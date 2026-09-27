import Foundation

/// How long a highlight film may run — the person's choice on the export sheet
/// (Chiu 2026-09-27).
///
/// **A choice, not a tunable**, so it is never read from `TrackingConfig.json`:
/// it travels from the sheet into the export as a value, the way the appearance
/// does. What each case *means* in seconds is config (`durationCeilingS`).
///
/// **Both lengths have a ceiling, and it beats the marks** (Chiu 2026-09-27):
/// the app's own choice is fitted under it; only what the person added
/// themselves can carry a film past it, and the sheet says so.
///
/// Applies to `RecapMode.highlight` only. `.full` has no ceiling by definition
/// and ignores it.
public enum FilmLength: String, CaseIterable, Equatable, Sendable {
    /// At most `total_duration_max_s` (90 s) — the length a Reel or a Short
    /// takes whole. The app's own choice of stops and photographs is cut to
    /// fit; a stop the person put in, or whose photographs they picked, is
    /// never cut, so only their own additions can carry it past the ceiling.
    case short
    /// The trip earns its stop count from its size (Chiu 2026-08-14) and the
    /// film is as long as that content — ≈ 88 s for a small trip, ≈ 212 s at
    /// the earned-stop cap — at most `standard_duration_max_s` (300 s), which
    /// only a trip whose marks keep many stops or lift many decks reaches.
    case standard
}
