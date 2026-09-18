import Foundation

/// **The credits a rendered film may owe its base map** (ADR 2026-09-12 (b)).
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
/// `AboutView` already applies to its two licence URLs. Coverage boxes below
/// are the same kind: licence facts, not tunables.
public enum RecapMapAttribution {

    // MARK: - The frozen OSM + OpenFreeMap credit (ADR 2026-09-13)

    /// The OSM half of the film credit, frozen by Chiu 2026-09-13.
    /// Present on every OpenFreeMap film, byte-identical, unchanged.
    public static let openFreeMapBase =
        "OpenFreeMap © OpenMapTiles Data from OpenStreetMap"

    // MARK: - Terrain sources whose licences require attribution

    /// A coarse lat/lon box for a terrain source's coverage, deliberately
    /// oversized. Kept here beside the strings it controls rather than in a
    /// shared geo library — coverage boxes are licence facts, not geometry.
    public struct CoverageBox {
        public let minLat: Double
        public let maxLat: Double
        public let minLon: Double
        public let maxLon: Double

        func intersects(minLat fMinLat: Double, maxLat fMaxLat: Double,
                        minLon fMinLon: Double, maxLon fMaxLon: Double) -> Bool {
            fMinLat <= maxLat && fMaxLat >= minLat
                && fMinLon <= maxLon && fMaxLon >= minLon
        }
    }

    /// A terrain elevation source that requires attribution under its licence
    /// (ADR 2026-09-18 (f)). Sources whose data is public domain (USGS SRTM,
    /// GMTED2010, 3DEP; NOAA ETOPO1; ArcticDEM) are **not listed** — their
    /// licences request credit but do not require it, and Chiu's rule is:
    /// credit only where required.
    ///
    /// Coverage boxes err LARGER than the actual data extent — a missed credit
    /// is a licence breach; an extra one costs a few characters. Each box was
    /// derived from the source's documented geographic scope, padded outward by
    /// at least one degree.
    ///
    /// Source of truth: tilezen/joerd `docs/attribution.md`, read 2026-09-18.
    ///
    /// ⚠️ **INFERRED** whether every source can appear at film zoom levels.
    /// joerd selects higher-resolution local DEMs at higher zooms and falls
    /// back to SRTM/GMTED at lower ones. A film's camera spans city-to-region
    /// scales (roughly z8–z14), where joerd may use only the global source for
    /// some tiles. The over-include rule means every source whose box the
    /// film intersects is credited regardless — if a later measurement shows
    /// a source never renders at these zooms, it can be removed then.
    public enum TerrainSource: CaseIterable {
        /// New Zealand — CC BY 3.0 New Zealand.
        /// "Crown copyright (c) Land Information New Zealand"
        case linz
        /// Australia — CC BY 4.0 International.
        /// "© Commonwealth of Australia (Geoscience Australia) 2017"
        case geoscienceAustralia
        /// EU-DEM — Copernicus, European Environment Agency, including Iceland.
        /// Prescribed: "Produced using Copernicus data and information funded
        /// by the European Union - EU-DEM layers"
        case euDEM
        /// England — Open Government Licence v3.
        /// "© Environment Agency copyright and/or database right 2015"
        case ukEnvironmentAgency
        /// Austria — CC BY 3.0 Österreich.
        /// "© offene Daten Österreichs – Digitales Geländemodell (DGM)"
        case austria
        /// Norway — CC BY 4.0 International.
        /// "© Kartverket"
        case kartverket
        /// Canada — Open Government Licence – Canada.
        /// "Contains information licensed under the Open Government Licence – Canada"
        case canada
        /// Mexico — free use of information licence.
        /// "Source: INEGI, Continental relief, 2016"
        case mexico

        /// Short-form credit for the film. INFERRED acceptable under each
        /// source's licence — CC BY permits "reasonable manner for the medium";
        /// Copernicus requires acknowledging EU funding (Delegated Regulation
        /// 1159/2013 Art. 3); government licences require naming the source.
        /// `AboutView` carries the full prescribed wording for each.
        public var filmCredit: String {
            switch self {
            case .linz: return "© LINZ"
            case .geoscienceAustralia: return "© Geoscience Australia"
            case .euDEM: return "EU-DEM (Copernicus)"
            case .ukEnvironmentAgency: return "© UK Environment Agency"
            case .austria: return "© data.gv.at"
            case .kartverket: return "© Kartverket"
            case .canada: return "CDEM (OGL Canada)"
            case .mexico: return "© INEGI"
            }
        }

        /// Coarse bounding box, deliberately oversized.
        public var coverageBox: CoverageBox {
            switch self {
            case .linz:
                return CoverageBox(minLat: -48, maxLat: -33, minLon: 165, maxLon: 179)
            case .geoscienceAustralia:
                return CoverageBox(minLat: -45, maxLat: -9, minLon: 112, maxLon: 155)
            case .euDEM:
                return CoverageBox(minLat: 34, maxLat: 72, minLon: -26, maxLon: 45)
            case .ukEnvironmentAgency:
                return CoverageBox(minLat: 49, maxLat: 62, minLon: -9, maxLon: 2)
            case .austria:
                return CoverageBox(minLat: 46, maxLat: 49, minLon: 9, maxLon: 18)
            case .kartverket:
                return CoverageBox(minLat: 57, maxLat: 82, minLon: 4, maxLon: 36)
            case .canada:
                return CoverageBox(minLat: 41, maxLat: 84, minLon: -141, maxLon: -52)
            case .mexico:
                return CoverageBox(minLat: 14, maxLat: 33, minLon: -118, maxLon: -86)
            }
        }
    }

    /// The full film credit for an OpenFreeMap film whose geographic extent
    /// is given (ADR 2026-09-18 (f)). The frozen OSM half is always present;
    /// terrain sources are appended only when the film's extent intersects
    /// their coverage **and** their licence requires attribution.
    ///
    /// Public-domain sources (USGS, NOAA, ArcticDEM) are never credited.
    public static func openFreeMap(
        minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    ) -> String {
        let required = TerrainSource.allCases.filter { source in
            source.coverageBox.intersects(
                minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon
            )
        }
        if required.isEmpty {
            return openFreeMapBase
        }
        return openFreeMapBase + " · Terrain: "
            + required.map(\.filmCredit).joined(separator: "/")
    }

    /// **What the parked souvenir substrate owes** — the self-hosted `.pmtiles`
    /// regions, whose vector data is OpenStreetMap's
    /// (`Config/RecapThemes/modern-minimal.json` declares the same string, which
    /// `MapLibreSubstrateTests` holds it to).
    ///
    /// Separate from the OpenFreeMap credit because they are different hosts of
    /// the same data, and a film must credit the one it actually drew. Naming
    /// both here is what stops the next substrate from being given whichever
    /// string was nearest.
    public static let openStreetMap = "© OpenStreetMap contributors"
}
