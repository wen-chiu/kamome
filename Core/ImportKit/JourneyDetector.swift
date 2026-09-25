import Foundation

/// Tunables for journey discovery — the `discovery` block of
/// `Config/TrackingConfig.json`, carried here so the module stays free of the
/// config loader (the app builds this from `TrackingConfig.Discovery`).
public struct JourneyDetectionConfig: Equatable, Sendable {
    public let homeCellDeg: Double
    public let awayRadiusM: Double
    public let journeyGapS: Double
    public let minPhotos: Int
    /// The country rule's step (ADR 2026-09-25): back in the home country ends
    /// a journey only when the step from the last photograph abroad is at least
    /// this long — a flight or a ferry home, not a drive back over a land border.
    public let homecomingMinJumpM: Double
    /// How far off a country's simplified outline a photograph still counts as
    /// in it: a beach, a harbour (`CountryBoundaries.country`).
    public let countryCoastBufferM: Double

    public init(
        homeCellDeg: Double, awayRadiusM: Double, journeyGapS: Double, minPhotos: Int,
        homecomingMinJumpM: Double, countryCoastBufferM: Double
    ) {
        self.homeCellDeg = homeCellDeg
        self.awayRadiusM = awayRadiusM
        self.journeyGapS = journeyGapS
        self.minPhotos = minPhotos
        self.homecomingMinJumpM = homecomingMinJumpM
        self.countryCoastBufferM = countryCoastBufferM
    }
}

/// Where the detector believes home is: the centre of the grid cell holding
/// photographs across the most distinct weeks. A guess, and reported as one.
public struct HomeEstimate: Equatable, Sendable {
    public let lat: Double
    public let lon: Double
    /// How many distinct weeks hold a photograph in the home cell — the evidence
    /// behind the guess. A library that is all travel has a weak home.
    public let weekCount: Int
}

/// One journey found in the photo library: a time-contiguous run of geotagged
/// photographs taken away from home. Not yet a trip — it becomes one through
/// `ImportService` when the user opens it.
public struct DiscoveredJourney: Equatable, Sendable, Identifiable {
    /// Stable across rescans: derived from the journey's first calendar day, so
    /// adding photographs to the library later does not change which trip this
    /// journey maps to. Since a homecoming ends a journey (2026-09-25), two can
    /// start on one day — out in the morning, home at noon, out again — and the
    /// second and later ones that day carry a `-2`, `-3` suffix; the first keeps
    /// the bare key every journey had before, so no stored trip loses its match.
    public let key: String
    /// Every photograph in the journey, time-ordered.
    public let photos: [ImportPhoto]
    public let startedAt: Double
    public let endedAt: Double
    /// Mean position of the photographs.
    public let centroidLat: Double
    public let centroidLon: Double
    /// The diagonal of the photographs' bounding box, in metres — how far the
    /// journey ranges. Decides whether it is named after a town or a country.
    public let extentM: Double

    public var id: String { key }
    public var photoCount: Int { photos.count }
}

/// What a scan of the library found.
public struct JourneyDetection: Equatable, Sendable {
    public let home: HomeEstimate?
    /// Newest first.
    public let journeys: [DiscoveredJourney]

    public static let empty = JourneyDetection(home: nil, journeys: [])
}

/// Finds journeys in a photo library (the Journey Discovery home, 2026-09-17).
///
/// Pure and deterministic: the same photographs and config always yield the same
/// journeys, in the same order, with the same keys. PhotoKit stays in the app.
///
/// **The heuristic, and why it is shaped this way.** A journey is time away from
/// home, so the detector first guesses home, then walks the photographs in time
/// order: one taken beyond `awayRadiusM` of home extends the current journey,
/// **one taken at home ends it** (Chiu 2026-09-25, R1), and so does a pause of
/// more than `journeyGapS` between two away photographs. Before R1 the home
/// photographs were dropped *before* cutting, so coming home never ended
/// anything: Japan and a Yilan weekend two days later became one journey.
/// A trip that passes back through home with the camera out is cut in two by
/// the same rule — accepted; the user can merge trips (ADR 2026-09-24 (b)).
///
/// **The country rule** (ADR 2026-09-25), when `countries` is given: the first
/// photograph back in the home country after one taken abroad ends the journey,
/// if the step from that last photograph abroad is at least
/// `homecomingMinJumpM`. Home country → abroad never cuts (Taiwan, then Japan,
/// is one trip); abroad → home country does (Japan, then Yilan, is two) — the
/// case R1 cannot see when nobody photographed home in between. A photograph at
/// sea, or anywhere no outline reaches, is no evidence either way. The minimum
/// step keeps a drive back over a land border (France → Switzerland → France)
/// from cutting. The home country is the one holding the home estimate, which
/// never leaves the phone; no home estimate, or one at sea, turns the rule off.
///
/// Home is the grid cell with
/// photographs across the most *distinct weeks* rather than the most
/// photographs: a fortnight abroad can out-shoot a year at home, but it cannot
/// out-span it. A library with no photographs at all has no home and no journeys.
public enum JourneyDetector {
    public static func detect(
        photos: [ImportPhoto], config: JourneyDetectionConfig, countries: CountryBoundaries? = nil
    ) -> JourneyDetection {
        let ordered = photos.sorted { lhs, rhs in
            lhs.timestamp != rhs.timestamp ? lhs.timestamp < rhs.timestamp : lhs.assetId < rhs.assetId
        }
        guard !ordered.isEmpty else { return .empty }

        let home = estimateHome(ordered, cellDeg: config.homeCellDeg)
        let homeCountry = home.flatMap {
            countries?.country(lat: $0.lat, lon: $0.lon, coastBufferM: config.countryCoastBufferM)
        }

        var runs: [[ImportPhoto]] = []
        var current: [ImportPhoto] = []
        // The latest photograph of the current journey taken outside the home country.
        var lastAbroad: ImportPhoto?
        for photo in ordered {
            let isHome = home.map {
                PhotoImportClusterer.haversineMeters($0.lat, $0.lon, photo.lat, photo.lon) <= config.awayRadiusM
            } ?? false
            if isHome {
                // Back home: whatever was under way is over.
                if !current.isEmpty { runs.append(current) }
                current = []
                lastAbroad = nil
                continue
            }
            if let last = current.last, photo.timestamp - last.timestamp > config.journeyGapS {
                runs.append(current)
                current = []
                lastAbroad = nil
            }
            switch countryStep(photo, lastAbroad: lastAbroad, countries: countries, home: homeCountry, config: config) {
            case .abroad:
                lastAbroad = photo
            case .homecoming:
                // Flown or sailed back into the home country: that trip is over.
                runs.append(current)
                current = []
                lastAbroad = nil
            case .noChange:
                break
            }
            current.append(photo)
        }
        if !current.isEmpty { runs.append(current) }

        var starts: [String: Int] = [:]
        let journeys = runs
            .filter { $0.count >= config.minPhotos }
            .map { run -> DiscoveredJourney in
                // `runs` is chronological, so the first journey of a day keeps the bare key.
                let base = key(startedAt: run[0].timestamp)
                starts[base, default: 0] += 1
                let ordinal = starts[base] ?? 1
                return makeJourney(run, key: ordinal == 1 ? base : "\(base)-\(ordinal)")
            }
            .sorted { $0.startedAt > $1.startedAt }
        return JourneyDetection(home: home, journeys: journeys)
    }

    /// The journey's key: its first calendar day, in UTC, as `journey-<epoch day>`.
    /// UTC because the photographs' zone is unknown and a day boundary that
    /// depends on the phone's current zone would rename a journey after a move.
    public static func key(startedAt: Double) -> String {
        "journey-\(Int((startedAt / 86_400).rounded(.down)))"
    }

    // MARK: - The country rule

    private enum CountryStep { case abroad, homecoming, noChange }

    /// What one photograph says under the country rule. `.noChange` without
    /// outlines or a home country, at sea, in the home country with nothing
    /// abroad before it, or back home by a step under `homecomingMinJumpM`.
    private static func countryStep(
        _ photo: ImportPhoto, lastAbroad: ImportPhoto?, countries: CountryBoundaries?,
        home: String?, config: JourneyDetectionConfig
    ) -> CountryStep {
        guard let countries, let home,
              let country = countries.country(lat: photo.lat, lon: photo.lon, coastBufferM: config.countryCoastBufferM)
        else { return .noChange }
        if country != home { return .abroad }
        guard let abroad = lastAbroad else { return .noChange }
        let step = PhotoImportClusterer.haversineMeters(abroad.lat, abroad.lon, photo.lat, photo.lon)
        return step >= config.homecomingMinJumpM ? .homecoming : .noChange
    }

    // MARK: - Home

    private static func estimateHome(_ ordered: [ImportPhoto], cellDeg: Double) -> HomeEstimate? {
        guard cellDeg > 0 else { return nil }
        struct Cell: Hashable { let lat: Int; let lon: Int }
        struct Sum { var lat = 0.0; var lon = 0.0; var total = 0.0 }
        var weeks: [Cell: Set<Int>] = [:]
        var sums: [Cell: Sum] = [:]
        for photo in ordered {
            let cell = Cell(lat: Int((photo.lat / cellDeg).rounded(.down)), lon: Int((photo.lon / cellDeg).rounded(.down)))
            weeks[cell, default: []].insert(Int((photo.timestamp / (7 * 86_400)).rounded(.down)))
            var sum = sums[cell] ?? Sum()
            sum.lat += photo.lat
            sum.lon += photo.lon
            sum.total += 1
            sums[cell] = sum
        }
        // Ties broken by the cell with more photographs, then deterministically.
        guard let best = weeks.max(by: { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            let lhsTotal = sums[lhs.key]?.total ?? 0
            let rhsTotal = sums[rhs.key]?.total ?? 0
            if lhsTotal != rhsTotal { return lhsTotal < rhsTotal }
            return (lhs.key.lat, lhs.key.lon) < (rhs.key.lat, rhs.key.lon)
        }), let sum = sums[best.key], sum.total >= 1 else { return nil }
        return HomeEstimate(lat: sum.lat / sum.total, lon: sum.lon / sum.total, weekCount: best.value.count)
    }

    // MARK: - Journeys

    private static func makeJourney(_ run: [ImportPhoto], key: String) -> DiscoveredJourney {
        let count = Double(run.count)
        let centroidLat = run.reduce(0.0) { $0 + $1.lat } / count
        let centroidLon = run.reduce(0.0) { $0 + $1.lon } / count
        let minLat = run.map(\.lat).min() ?? centroidLat
        let maxLat = run.map(\.lat).max() ?? centroidLat
        let minLon = run.map(\.lon).min() ?? centroidLon
        let maxLon = run.map(\.lon).max() ?? centroidLon
        return DiscoveredJourney(
            key: key,
            photos: run,
            startedAt: run[0].timestamp,
            endedAt: run[run.count - 1].timestamp,
            centroidLat: centroidLat,
            centroidLon: centroidLon,
            extentM: PhotoImportClusterer.haversineMeters(minLat, minLon, maxLat, maxLon)
        )
    }
}
