import Foundation

/// **The credits a rendered film may owe its base map** (ADR 2026-09-12).
///
/// Chiu decided 2026-08-17 that attribution lives in the app's interface and
/// never in the rendered film. That decision was made when the film's imagery
/// was Apple's, and it is **amended, not overturned**: an exported MP4 built on
/// OSM-derived tiles is a *produced work* under ODbL, and the licence binds the
/// work rather than the screen that made it. `UI/About/AboutView.swift` keeps
/// everything it carries — Geoapify's free plan requires attribution in its own
/// right and this changes nothing about that.
///
/// **Not localized, and that is the same argument the Geoapify line already
/// won** (`LocalizationTests.testAttributionCarriesBothLicenceObligations`):
/// the required thing is the *format*, so a well-meaning translation pass would
/// break the obligation while looking like an improvement. The film's chrome
/// already works this way — `RecapWordmark`, the HUD's `km`, and the boarding
/// pass's `FROM` / `TO` are English literals by decision, which is also what
/// keeps a frame byte-identical on any device.
///
/// **Constants rather than `Config/TrackingConfig.json`.** Rule 7 governs
/// *tunables*; changing one of these is a licence breach, not a tuning decision,
/// and a key someone may edit is the wrong shape for that — the same reasoning
/// `AboutView` already applies to its two licence URLs.
public enum RecapMapAttribution {
    /// **What OpenFreeMap asks for**, VERIFIED 2026-09-09 from openfreemap.org
    /// and from the TileJSON its styles declare.
    ///
    /// Two clauses with two different standings, worth keeping straight: the
    /// `Data from OpenStreetMap` half is the **ODbL obligation** and is not
    /// optional; the `OpenFreeMap © OpenMapTiles` half is asked-for rather than
    /// required. Carried whole because a credit that drops the half its host
    /// asks for, on a free planet-wide CDN with no key and no request limit, is
    /// a poor trade for 26 characters.
    public static let openFreeMap = "OpenFreeMap © OpenMapTiles Data from OpenStreetMap"

    /// **What the parked souvenir substrate owes** — the self-hosted `.pmtiles`
    /// regions, whose vector data is OpenStreetMap's
    /// (`Config/RecapThemes/modern-minimal.json` declares the same string, which
    /// `MapLibreSubstrateTests` holds it to).
    ///
    /// Separate from `openFreeMap` because they are different hosts of the same
    /// data, and a film must credit the one it actually drew. Naming both here
    /// is what stops the next substrate from being given whichever string was
    /// nearest.
    public static let openStreetMap = "© OpenStreetMap contributors"
}
