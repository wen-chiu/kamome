import Foundation

/// **The country a trip is in, and how wide that country is** — what the
/// opening's title card is held over (Chiu 2026-08-31).
///
/// ## Why a table, and why it is small
///
/// The opening's first beat answers *where in the world is this*. Until now it
/// could not: `establishing` was only ever an installed `.pmtiles` region's
/// extent, MapLibre was parked on 2026-08-15, and nothing has installed one
/// since — so the "country" beat has always been *this trip's own bounds ×
/// `country_view_padding`*, which on a compact trip inside a large country is
/// geographically meaningless. That is the "看不到整個澳洲… 不知道在哪裡"
/// complaint, in one line (`Docs/handoff-crop-scaling.md` §4).
///
/// Chiu chose a **built-in table** over asking MapKit or `CLGeocoder`, for two
/// reasons that are not about convenience:
///
/// - **A film must render with no network.** Every Apple API that returns a
///   country extent is a round trip; `CLPlacemark.region` exists only on a
///   response. A table is the only option that satisfies this on its own.
/// - **§0.** A geocoded country lookup would send a real coordinate off-device
///   *to draw a wider opening* — a new exception beyond routing and one share,
///   and therefore a product decision. This needs none: the lookup is
///   point-in-box against a constant, so no coordinate leaves the process.
///
/// ## What is deliberately NOT in it
///
/// **A country whose single bounding box would be a lie is left out**, not
/// approximated. One box for the United States spans Alaska to Florida, so a
/// trip in California would be established by a frame in which California is a
/// speck and most of the picture is ocean — worse than the trip-bounds fallback
/// it replaced. The same is true of France with its overseas départements and of
/// Norway with Svalbard. Those need more than one box per country, which is a
/// bigger design than a title card justifies today.
///
/// So this ships the countries Kamome actually renders, each a contiguous extent
/// a single box describes honestly, and **an unknown country falls back loudly**
/// to the previous behaviour rather than guessing (`CameraPath.buildWideOpening`
/// logs which happened). Extending it is adding a row.
///
/// ⚠️ **The boxes are approximate by construction** — they are a backdrop for a
/// title card, which is chrome, not a claim about geography the way a drawn road
/// is (`CLAUDE.md` rule 5). They are rounded outward to whole tenths of a degree
/// so no row pretends to a precision it does not have.
public enum CountryExtent {
    /// One country's extent, and the ISO 3166-1 alpha-2 code that names it.
    ///
    /// The code rather than a name because the **name is the system's job**:
    /// `Locale.localizedString(forRegionCode:)` answers in the viewer's own
    /// language, offline, so a Chinese-language film says 日本 and an English one
    /// says Japan from the same row. A name in this table would be one language
    /// pretending to be all of them, and Kamome names places natively (§1.7).
    public struct Country: Equatable {
        public let isoCode: String
        public let bounds: RecapBounds

        init(_ isoCode: String, minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
            self.isoCode = isoCode
            bounds = RecapBounds(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon)
        }

        /// The country's name in the viewer's language, or nil when the system
        /// has none — in which case the title card says the place and stops,
        /// rather than printing a two-letter code at a viewer.
        public func localizedName(locale: Locale = .current) -> String? {
            locale.localizedString(forRegionCode: isoCode)
        }
    }

    /// Every country Kamome can establish. Ordered by area ascending, so a point
    /// inside two boxes resolves to the more specific one — the only overlap
    /// today is Taiwan sitting inside no other row, but the ordering makes the
    /// rule explicit rather than incidental.
    public static let all: [Country] = [
        Country("TW", minLat: 21.8, minLon: 119.3, maxLat: 25.4, maxLon: 122.1),
        Country("IS", minLat: 63.2, minLon: -24.6, maxLat: 66.6, maxLon: -13.4),
        Country("FI", minLat: 59.7, minLon: 20.5, maxLat: 70.1, maxLon: 31.6),
        Country("NZ", minLat: -47.3, minLon: 166.4, maxLat: -34.3, maxLon: 178.6),
        Country("JP", minLat: 24.0, minLon: 122.9, maxLat: 45.6, maxLon: 146.0),
        Country("AU", minLat: -43.7, minLon: 112.9, maxLat: -10.0, maxLon: 153.7)
    ]

    /// The country containing `lat`/`lon`, or nil when none does.
    ///
    /// Point-in-box, smallest first. nil is a **real answer** and the caller must
    /// say so out loud rather than substituting something that looks like a
    /// country (`Arch.md` §6).
    public static func containing(lat: Double, lon: Double) -> Country? {
        all.first { country in
            lat >= country.bounds.minLat && lat <= country.bounds.maxLat
                && lon >= country.bounds.minLon && lon <= country.bounds.maxLon
        }
    }
}
