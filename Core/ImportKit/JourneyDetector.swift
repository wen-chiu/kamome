import Foundation

/// Tunables for journey discovery — the `discovery` block of
/// `Config/TrackingConfig.json`, carried here so the module stays free of the
/// config loader (the app builds this from `TrackingConfig.Discovery`).
public struct JourneyDetectionConfig: Equatable, Sendable {
    public let homeCellDeg: Double
    public let awayRadiusM: Double
    public let journeyGapS: Double
    public let minPhotos: Int

    public init(homeCellDeg: Double, awayRadiusM: Double, journeyGapS: Double, minPhotos: Int) {
        self.homeCellDeg = homeCellDeg
        self.awayRadiusM = awayRadiusM
        self.journeyGapS = journeyGapS
        self.minPhotos = minPhotos
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
    /// journey maps to. Two journeys cannot start on the same day — the gap rule
    /// keeps them at least `journeyGapS` apart.
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
/// home, so the detector first guesses home, then keeps only photographs taken
/// beyond `awayRadiusM` of it, then cuts that run wherever two consecutive
/// photographs are more than `journeyGapS` apart. Home is the grid cell with
/// photographs across the most *distinct weeks* rather than the most
/// photographs: a fortnight abroad can out-shoot a year at home, but it cannot
/// out-span it. A library with no photographs at all has no home and no journeys.
public enum JourneyDetector {
    public static func detect(photos: [ImportPhoto], config: JourneyDetectionConfig) -> JourneyDetection {
        let ordered = photos.sorted { lhs, rhs in
            lhs.timestamp != rhs.timestamp ? lhs.timestamp < rhs.timestamp : lhs.assetId < rhs.assetId
        }
        guard !ordered.isEmpty else { return .empty }

        let home = estimateHome(ordered, cellDeg: config.homeCellDeg)
        let away: [ImportPhoto]
        if let home {
            away = ordered.filter {
                PhotoImportClusterer.haversineMeters(home.lat, home.lon, $0.lat, $0.lon) > config.awayRadiusM
            }
        } else {
            away = ordered
        }

        var runs: [[ImportPhoto]] = []
        var current: [ImportPhoto] = []
        for photo in away {
            if let last = current.last, photo.timestamp - last.timestamp > config.journeyGapS {
                runs.append(current)
                current = []
            }
            current.append(photo)
        }
        if !current.isEmpty { runs.append(current) }

        let journeys = runs
            .filter { $0.count >= config.minPhotos }
            .map(makeJourney)
            .sorted { $0.startedAt > $1.startedAt }
        return JourneyDetection(home: home, journeys: journeys)
    }

    /// The journey's key: its first calendar day, in UTC, as `journey-<epoch day>`.
    /// UTC because the photographs' zone is unknown and a day boundary that
    /// depends on the phone's current zone would rename a journey after a move.
    public static func key(startedAt: Double) -> String {
        "journey-\(Int((startedAt / 86_400).rounded(.down)))"
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

    private static func makeJourney(_ run: [ImportPhoto]) -> DiscoveredJourney {
        let count = Double(run.count)
        let centroidLat = run.reduce(0.0) { $0 + $1.lat } / count
        let centroidLon = run.reduce(0.0) { $0 + $1.lon } / count
        let minLat = run.map(\.lat).min() ?? centroidLat
        let maxLat = run.map(\.lat).max() ?? centroidLat
        let minLon = run.map(\.lon).min() ?? centroidLon
        let maxLon = run.map(\.lon).max() ?? centroidLon
        return DiscoveredJourney(
            key: key(startedAt: run[0].timestamp),
            photos: run,
            startedAt: run[0].timestamp,
            endedAt: run[run.count - 1].timestamp,
            centroidLat: centroidLat,
            centroidLon: centroidLon,
            extentM: PhotoImportClusterer.haversineMeters(minLat, minLon, maxLat, maxLon)
        )
    }
}
