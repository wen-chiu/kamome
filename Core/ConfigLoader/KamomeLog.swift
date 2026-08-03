import Foundation
import os

/// The few decisions the app makes **silently** that a dogfooder cannot
/// otherwise see (2026-08-01, after the first real-device import).
///
/// Kamome is deliberately forgiving: a routing server that cannot be reached
/// keeps the raw geometry and draws it dashed (PD-2), and a trip with no
/// installed map region falls back to Apple's map. Both are correct — a film
/// still comes out — and both are *invisible*. The Miyakojima device test
/// produced a complete film in which every leg was dashed, the duration was the
/// legacy 30 s, and there was no way to tell from the artifact which of four
/// possible causes had fired.
///
/// So the rule is: **anything that degrades the film without failing gets a log
/// line naming the reason.** Not analytics, not telemetry — nothing leaves the
/// device. `Logger` writes to the unified log, which is readable in Console.app
/// with the phone attached, or afterwards with `log collect --device`.
///
/// Filter to `subsystem:com.chiu.kamome` to see only these.
public enum KamomeLog {
    /// Route reconstruction and map-matching (`Core/RouteMatching`, PD-1/PD-2).
    /// Every leg's verdict, and the base URL it was asked of — the two facts the
    /// all-dashed failure needs and could not previously supply.
    public static let routing = Logger(subsystem: subsystem, category: "routing")
    /// Which map region, which duration plan, which base map — the choices that
    /// silently reshape a film (`RecapModel`, `LinearTimeline`).
    public static let recap = Logger(subsystem: subsystem, category: "recap")
    /// Reverse-geocoding for stop names (§4.2). Its failures used to be silent,
    /// which made a film of "Unnamed stop" cards impossible to explain.
    public static let geocode = Logger(subsystem: subsystem, category: "geocode")
    /// Photo import: how many photos, how they clustered.
    public static let importing = Logger(subsystem: subsystem, category: "import")

    private static let subsystem = "com.chiu.kamome"
}
