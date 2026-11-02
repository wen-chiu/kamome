import Foundation
import KamomeImportKit
import KamomeRouteMatching
import KamomeTrackingEngine

/// **The trips `RoutePathScenarioProbeTests` makes films of** — photographs and
/// GPS fixes at public places, and a routing stub that knows where the sea is.
/// Synthetic, none of them a trip anyone took (`CLAUDE.md` §0).
enum RoutePathScenarios {
    struct Place {
        let lat: Double
        let lon: Double
    }

    // MARK: - Places (public landmarks)

    static let seoul = Place(lat: 37.5665, lon: 126.9780)
    static let suwon = Place(lat: 37.2636, lon: 127.0286)
    static let incheon = Place(lat: 37.4602, lon: 126.4407)
    static let busan = Place(lat: 35.1028, lon: 129.0403)
    static let haneda = Place(lat: 35.5494, lon: 139.7798)
    static let tokyo = Place(lat: 35.6812, lon: 139.7671)
    static let yokohama = Place(lat: 35.4437, lon: 139.6380)
    static let kamakura = Place(lat: 35.3192, lon: 139.5467)
    static let kyoto = Place(lat: 35.0116, lon: 135.7681)
    static let osaka = Place(lat: 34.6937, lon: 135.5023)
    static let fukuoka = Place(lat: 33.5902, lon: 130.4017)
    static let chitose = Place(lat: 42.7752, lon: 141.6923)
    static let sapporo = Place(lat: 43.0618, lon: 141.3545)
    static let otaru = Place(lat: 43.1907, lon: 140.9947)
    static let furano = Place(lat: 43.3420, lon: 142.3832)
    static let asahikawa = Place(lat: 43.7706, lon: 142.3650)
    static let bangkok = Place(lat: 13.7563, lon: 100.5018)
    static let suvarnabhumi = Place(lat: 13.6900, lon: 100.7501)
    static let ayutthaya = Place(lat: 14.3532, lon: 100.5689)
    static let huaHin = Place(lat: 12.5684, lon: 99.9577)
    static let heathrow = Place(lat: 51.4700, lon: -0.4543)
    static let london = Place(lat: 51.5074, lon: -0.1278)
    static let oxford = Place(lat: 51.7520, lon: -1.2577)
    static let dover = Place(lat: 51.1279, lon: 1.3134)
    static let calais = Place(lat: 50.9513, lon: 1.8587)
    static let paris = Place(lat: 48.8566, lon: 2.3522)
    static let cdg = Place(lat: 49.0097, lon: 2.5479)
    static let lisbon = Place(lat: 38.7223, lon: -9.1393)
    static let porto = Place(lat: 41.1579, lon: -8.6291)
    static let salamanca = Place(lat: 40.9701, lon: -5.6635)
    static let madrid = Place(lat: 40.4168, lon: -3.7038)
    static let zaragoza = Place(lat: 41.6488, lon: -0.8891)
    static let barcelona = Place(lat: 41.3874, lon: 2.1686)
    static let montpellier = Place(lat: 43.6108, lon: 3.8767)
    static let nice = Place(lat: 43.7102, lon: 7.2620)
    static let genoa = Place(lat: 44.4056, lon: 8.9463)
    static let milan = Place(lat: 45.4642, lon: 9.1900)
    static let honolulu = Place(lat: 21.3187, lon: -157.9225)
    static let waikiki = Place(lat: 21.2793, lon: -157.8292)
    static let northShore = Place(lat: 21.6400, lon: -158.0630)
    static let lax = Place(lat: 33.9416, lon: -118.4085)
    static let santaMonica = Place(lat: 34.0195, lon: -118.4912)
    static let sydney = Place(lat: -33.9399, lon: 151.1753)
    static let dubai = Place(lat: 25.2532, lon: 55.3657)
    static let oslo = Place(lat: 60.1976, lon: 11.1004)
    static let tromso = Place(lat: 69.6829, lon: 18.9189)
    static let alta = Place(lat: 69.9689, lon: 23.2716)
    static let northCape = Place(lat: 71.1685, lon: 25.7838)
    static let coimbra = Place(lat: 40.2033, lon: -8.4103)
    static let sintra = Place(lat: 38.8029, lon: -9.3817)
    static let cascais = Place(lat: 38.6979, lon: -9.4215)
    static let evora = Place(lat: 38.5714, lon: -7.9135)
    static let newYork = Place(lat: 40.6413, lon: -73.7781)
    static let manhattan = Place(lat: 40.7580, lon: -73.9855)
    static let boston = Place(lat: 42.3601, lon: -71.0589)
    /// In the Korea Strait, on a ferry's line.
    static let strait1 = Place(lat: 34.60, lon: 129.40)
    static let strait2 = Place(lat: 34.05, lon: 129.95)

    // MARK: - Geography the stub answers from

    /// Which drivable land a point is on, nil for open water. Coarse boxes —
    /// enough to say "these two places share a road network" for the places
    /// above, and nothing more.
    enum Land {
        struct Box {
            let name: String?
            let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

            func contains(_ lat: Double, _ lon: Double) -> Bool {
                (minLat...maxLat).contains(lat) && (minLon...maxLon).contains(lon)
            }
        }

        /// First match wins. The Korea Strait comes first: Busan sits north of
        /// it, Fukuoka south, and the two boxes either side overlap it.
        static let boxes = [
            Box(name: nil, minLat: 33.7, maxLat: 34.9, minLon: 128.9, maxLon: 130.2),
            Box(name: "jeju", minLat: 33.1, maxLat: 33.6, minLon: 126.1, maxLon: 127.0),
            Box(name: "korea", minLat: 33.0, maxLat: 38.7, minLon: 124.5, maxLon: 129.6),
            Box(name: "hokkaido", minLat: 41.35, maxLat: 45.6, minLon: 139.3, maxLon: 146.0),
            Box(name: "honshu", minLat: 30.9, maxLat: 41.6, minLon: 129.6, maxLon: 142.2),
            Box(name: "britain", minLat: 49.9, maxLat: 58.7, minLon: -6.5, maxLon: 1.8),
            Box(name: "europe", minLat: 35.0, maxLat: 71.5, minLon: -10.0, maxLon: 40.0),
            Box(name: "indochina", minLat: 5.0, maxLat: 28.0, minLon: 97.0, maxLon: 110.0),
            Box(name: "oahu", minLat: 21.2, maxLat: 21.8, minLon: -158.3, maxLon: -157.6),
            Box(name: "america", minLat: 25.0, maxLat: 49.5, minLon: -125.0, maxLon: -67.0),
            Box(name: "australia", minLat: -39.5, maxLat: -10.0, minLon: 113.0, maxLon: 154.0),
            Box(name: "arabia", minLat: 22.0, maxLat: 27.0, minLon: 51.0, maxLon: 57.0)
        ]

        static func of(_ lat: Double, _ lon: Double) -> String? {
            boxes.first { $0.contains(lat, lon) }?.name
        }
    }

    /// **Answers the way Geoapify does** (`GeoapifyRouteProvider`): a waypoint
    /// with no land under it is `No suitable edges` → `.offTheRoadNetwork`
    /// (the walk retry finds nothing either); waypoints on two lands no car
    /// ferry joins are `No path` → `.noRoadHere`; otherwise a road through the
    /// waypoints, about 15% longer than the straight line.
    ///
    /// `ferries` names land pairs the **drive** profile is assumed to cross by
    /// car ferry (INFERRED — whether Geoapify's drive mode takes ferries is not
    /// measured in this repository).
    struct Geography: RouteReconstructing {
        var offline = false
        var ferries: Set<[String]> = []

        func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
            if offline { throw RouteProviderFailure.unreachable("probe: offline") }
            let lands = waypoints.map { Land.of($0.lat, $0.lon) }
            if lands.contains(where: { $0 == nil }) { return .offTheRoadNetwork }
            for (from, to) in zip(lands, lands.dropFirst()) where from != to {
                guard let from, let to, ferries.contains([from, to].sorted()) else { return .noRoadHere }
            }
            return .routed(RouteMatchOutcome(geometry: Self.road(through: waypoints), confidence: 1))
        }

        /// A half-sine bow between each pair of waypoints — about 1.15× the
        /// straight line, a sample every ~2 km.
        static func road(through waypoints: [RouteMatchPoint]) -> [GeoPoint] {
            var points = [GeoPoint(lat: waypoints[0].lat, lon: waypoints[0].lon)]
            for (start, end) in zip(waypoints, waypoints.dropFirst()) {
                let lengthM = Geo.distanceM(latA: start.lat, lonA: start.lon, latB: end.lat, lonB: end.lon)
                let steps = max(8, min(400, Int(lengthM / 2000)))
                let dLat = end.lat - start.lat, dLon = end.lon - start.lon
                for step in 1...steps {
                    let fraction = Double(step) / Double(steps)
                    let bow = 0.25 * sin(.pi * fraction)
                    points.append(GeoPoint(
                        lat: start.lat + dLat * fraction - dLon * bow,
                        lon: start.lon + dLon * fraction + dLat * bow
                    ))
                }
            }
            return points
        }
    }

    // MARK: - Photographs

    static let epoch = 1_777_593_600.0 // 2026-05-01 00:00 UTC

    /// `count` photographs at `place`, ten minutes apart, a few tens of metres
    /// between them — one stop when `count` ≥ 2.
    static func visit(_ id: String, _ place: Place, hour: Double, count: Int = 3, altitude: Double? = nil) -> [ImportPhoto] {
        (0..<count).map { index in
            ImportPhoto(
                assetId: "\(id)-\(index)", timestamp: epoch + hour * 3600 + Double(index) * 600,
                lat: place.lat + Double(index) * 0.0003, lon: place.lon + Double(index % 2) * 0.0003,
                altitudeLowerBoundM: altitude
            )
        }
    }

    // MARK: - Scenarios

    enum Form: String { case local, departure, any }

    struct Scenario {
        let name: String
        let photos: [ImportPhoto]
        var routing = Geography()
        var form: Form = .any
    }

    // MARK: - Recorded GPS, with a flight

    static func drive(_ from: Place, _ to: Place, startS: Double, kmh: Double, everyS: Double = 5) -> [LocationSample] {
        let metres = Geo.distanceM(latA: from.lat, lonA: from.lon, latB: to.lat, lonB: to.lon)
        let steps = max(2, Int(metres / (kmh / 3.6) / everyS))
        return (0...steps).map { step in
            let fraction = Double(step) / Double(steps)
            return LocationSample(
                ts: startS + Double(step) * everyS,
                lat: from.lat + (to.lat - from.lat) * fraction, lon: from.lon + (to.lon - from.lon) * fraction,
                hAccM: 8, speedMps: kmh / 3.6
            )
        }
    }

    static func stay(_ at: Place, startS: Double, minutes: Double, everyS: Double = 15) -> [LocationSample] {
        (0...Int(minutes * 60 / everyS)).map {
            LocationSample(ts: startS + Double($0) * everyS, lat: at.lat, lon: at.lon, hAccM: 8, speedMps: 0)
        }
    }

    /// Seoul → a drive to the airport → a flight → a drive at the destination,
    /// recorded; the flight either dark (`airborneGPS` false) or sampled.
    static func recordedFlight(airborneGPS: Bool) -> [LocationSample] {
        var samples = stay(seoul, startS: epoch, minutes: 20)
        var clock = samples.last!.ts + 5
        func then(_ more: [LocationSample]) {
            samples += more
            clock = more.last!.ts + 5
        }
        then(drive(seoul, incheon, startS: clock, kmh: 60))
        then(stay(incheon, startS: clock, minutes: 40))
        if airborneGPS {
            then(drive(incheon, chitose, startS: clock, kmh: 800, everyS: 30))
        } else {
            clock += 3 * 3600
        }
        then(stay(chitose, startS: clock, minutes: 30))
        then(drive(chitose, sapporo, startS: clock, kmh: 60))
        then(stay(sapporo, startS: clock, minutes: 40))
        then(drive(sapporo, otaru, startS: clock, kmh: 50))
        then(stay(otaru, startS: clock, minutes: 40))
        return samples
    }
}
