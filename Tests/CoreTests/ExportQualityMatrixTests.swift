import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **Every shape of trip a person can export, run through the whole film plan**
/// — the timeline, the camera, the substrate's band and the snapshot stations —
/// and checked frame by frame against what an export needs to finish and look
/// right. No map is drawn and no network is touched: each check is one the
/// render loop would otherwise make at minute thirty, on a phone.
///
/// Two families, because the film has two forms (`RecapFilmType`):
///
/// - **local** — one region, no crossing: a city walk, a day's drive, a long
///   road trip, a loop, an out-and-back, a trip near a pole, on the equator, on
///   180°, all-dashed legs, unrouted legs, stops with no photographs, a short
///   no-road hop at the end;
/// - **with a departure** — the type-2 film that opens on the flight and
///   carries a boarding pass: from an airport photograph alone, after a drive
///   to the airport, a short island hop, a long-haul past the flight frame's
///   limit, across 180°, to the high Arctic, a domestic flight, a destination
///   of one photograph, a transit, two destinations, a photograph taken in the
///   air, a crossing nobody named a country for.
///
/// What every film must hold (the invariants, each named in its message):
///
/// 1. it builds, with a finite positive length and a frame count that matches;
/// 2. every frame's camera is finite, positive, inside the substrate's world;
/// 3. the vehicle's position and heading are finite on every frame;
/// 4. the stations partition the film, in order, with no gap and no overlap;
/// 5. **every frame is contained by its station on the projection MapLibre
///    draws** — the check `SnapshotReprojection` makes at render time, which
///    fails the export (`ContainmentError`) if it does not hold;
/// 6. the odometer never runs backwards, never goes negative, and ends on the
///    local journey's own distance;
/// 7. a stop's photo deck is never on screen under the end card;
/// 8. a type-2 film opens on the flight with its pass and both ends marked —
///    or, past the drawn-flight limit, on the frozen card with neither; a
///    local film never shows a pass or a flight end;
/// 9. the title card opens the film and the end card closes it;
/// 10. a flight the film does not draw is cut, not flown (#275): no frame wider
///     than the opening's, nothing flies, the departure's photographs play.
///
/// Synthetic geometry between public places, none of them a trip anyone took
/// (`CLAUDE.md` §0).
final class ExportQualityMatrixTests: XCTestCase {
    typealias Place = RecapCoordinate

    private func shipped() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    // MARK: - Places (public landmarks; synthetic trips)

    private let incheon = Place(lat: 37.46, lon: 126.44)
    private let seoul = Place(lat: 37.57, lon: 126.98)
    private let sapporo = Place(lat: 43.06, lon: 141.35)
    private let lisbon = Place(lat: 38.72, lon: -9.14)
    private let porto = Place(lat: 41.15, lon: -8.61)
    private let edinburgh = Place(lat: 55.95, lon: -3.19)
    private let northCape = Place(lat: 71.17, lon: 25.78)
    private let longyearbyen = Place(lat: 78.22, lon: 15.65)
    private let oslo = Place(lat: 60.19, lon: 11.10)
    private let quito = Place(lat: -0.18, lon: -78.47)
    private let honolulu = Place(lat: 21.32, lon: -157.92)
    private let london = Place(lat: 51.47, lon: -0.45)
    private let singapore = Place(lat: 1.36, lon: 103.99)
    private let johannesburg = Place(lat: -26.14, lon: 28.25)
    private let capeTown = Place(lat: -33.97, lon: 18.60)
    private let barcelona = Place(lat: 41.30, lon: 2.08)
    private let palma = Place(lat: 39.55, lon: 2.73)
    private let dubai = Place(lat: 25.25, lon: 55.36)
    private let banff = Place(lat: 51.18, lon: -115.57)
    private let vancouver = Place(lat: 49.19, lon: -123.18)

    // MARK: - Builders

    /// A small loop of `count` places around `centre`, `radiusDeg` out.
    private func loop(_ centre: Place, radiusDeg: Double = 0.3, count: Int = 4) -> [Place] {
        (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            return Place(lat: centre.lat + radiusDeg * sin(angle), lon: centre.lon + radiusDeg * cos(angle))
        }
    }

    /// `count` places evenly along the straight line from `start` to `end`.
    private func line(_ start: Place, _ end: Place, count: Int) -> [Place] {
        (0..<count).map { index in
            let fraction = count > 1 ? Double(index) / Double(count - 1) : 0
            return Place(lat: start.lat + (end.lat - start.lat) * fraction,
                         lon: start.lon + (end.lon - start.lon) * fraction)
        }
    }

    /// One stop per place, joined in order. A leg in `crossings` is a straight
    /// two-point crossing; every other leg is a 30-vertex road taken the short
    /// way across 180°. `countries[i]` is the code stop naming stored for stop
    /// i ("" = asked, at sea); a crossing's two codes are the nearest named
    /// stops either side, as `RecapComposer.crossingCountryCodes` takes them.
    private func trip(
        _ places: [Place],
        crossings: Set<Int> = [],
        photos: [Int]? = nil,
        countries: [String]? = nil,
        dashed: Bool = false,
        established: Bool = true
    ) -> RecapTrip {
        let stops = places.enumerated().map { index, place in
            let count = photos?[index] ?? 3
            return RecapTrip.Stop(
                coordinate: place, name: "Stop \(index)", dayLabel: "Day \(index / 3 + 1)",
                photos: (0..<count).map { .asset("p\(index)-\($0)") },
                dwellS: 3600, locality: "Town \(index)"
            )
        }
        let legs = zip(places, places.dropFirst()).enumerated().map { index, pair -> RecapTrip.Leg in
            let isCrossing = crossings.contains(index)
            let eastward = Antimeridian.normalized(pair.1.lon - pair.0.lon)
            let coordinates = isCrossing ? [pair.0, pair.1] : (0...30).map { step in
                let fraction = Double(step) / 30
                return Place(lat: pair.0.lat + (pair.1.lat - pair.0.lat) * fraction,
                             lon: Antimeridian.normalized(pair.0.lon + eastward * fraction))
            }
            var codes: (origin: String?, destination: String?) = (nil, nil)
            if isCrossing, let countries {
                codes = (countries[...index].last { !$0.isEmpty }, countries[(index + 1)...].first { !$0.isEmpty })
            }
            return RecapTrip.Leg(
                coordinates: coordinates, mode: .drive,
                provenance: isCrossing || dashed ? .inferred : .reconstructed,
                isCrossing: isCrossing, countryCodes: codes
            )
        }
        return RecapTrip(
            legs: legs, stops: stops, title: "Trip", subtitle: "", endCardFigures: [],
            journeyDates: "1 MAY 2026 – 9 MAY 2026", everyLegRoutabilityEstablished: established
        )
    }

    // MARK: - The matrix

    enum Form { case local, departure }

    struct Case {
        let name: String
        let form: Form
        let trip: RecapTrip
        /// Whether the boarding pass is expected (a departure whose two ends
        /// both have a country).
        var pass = true
        /// Whether the opening draws the flight. A pair further apart than
        /// `crossing_flight_max_longitude_deg` takes the other main path, the
        /// frozen card, which flies nothing over the opening and carries no
        /// pass (`CrossingFraming`, ADR 2026-09-04).
        var drawsTheFlight = true
    }

    private var localCases: [Case] {
        let walk = line(Place(lat: 38.710, lon: -9.140), Place(lat: 38.713, lon: -9.135), count: 4)
        return [
            Case(name: "city walk, 4 stops in 500 m", form: .local, trip: trip(walk)),
            Case(name: "one stop at each end of one road", form: .local, trip: trip([lisbon, porto])),
            Case(name: "day drive, 6 stops", form: .local, trip: trip(line(lisbon, porto, count: 6))),
            Case(name: "long road trip, 21 stops over 900 km", form: .local,
                 trip: trip(line(vancouver, banff, count: 11) + line(banff, Place(lat: 53.5, lon: -113.5), count: 11)
                    .dropFirst())),
            Case(name: "loop back to the start", form: .local,
                 trip: trip(loop(edinburgh, radiusDeg: 0.5, count: 6) + [loop(edinburgh, radiusDeg: 0.5, count: 6)[0]])),
            Case(name: "out and back on one road", form: .local,
                 trip: trip(line(lisbon, porto, count: 4) + line(porto, lisbon, count: 4).dropFirst())),
            Case(name: "the far north, 71°N", form: .local, trip: trip(loop(northCape, radiusDeg: 0.6, count: 5))),
            Case(name: "the high Arctic, 78°N", form: .local, trip: trip(loop(longyearbyen, radiusDeg: 0.2, count: 4))),
            Case(name: "across the equator", form: .local,
                 trip: trip(line(Place(lat: -0.6, lon: -78.5), Place(lat: 0.4, lon: -78.1), count: 5))),
            Case(name: "an island on 180°", form: .local,
                 trip: trip([Place(lat: -16.80, lon: 179.70), Place(lat: -16.90, lon: 179.95),
                             Place(lat: -16.95, lon: -179.90), Place(lat: -16.70, lon: -179.80)])),
            Case(name: "every leg dashed (nothing matched)", form: .local,
                 trip: trip(line(lisbon, porto, count: 5), dashed: true)),
            Case(name: "routing never answered", form: .local,
                 trip: trip(line(lisbon, porto, count: 5), established: false)),
            Case(name: "stops with no photographs", form: .local,
                 trip: trip(line(lisbon, porto, count: 5), photos: [0, 0, 3, 0, 0])),
            Case(name: "one stop with 40 photographs", form: .local,
                 trip: trip(line(lisbon, porto, count: 4), photos: [3, 40, 3, 3])),
            Case(name: "a short no-road hop at the end (a beach photograph)", form: .local,
                 trip: trip(loop(palma, radiusDeg: 0.3, count: 5) + [Place(lat: 39.25, lon: 2.73)], crossings: [4]))
        ]
    }

    private var departureCases: [Case] {
        let hokkaido = loop(sapporo, radiusDeg: 0.5, count: 5)
        let kr = "KR", jp = "JP"
        return [
            Case(name: "airport photograph only, then the destination", form: .departure,
                 trip: trip([incheon] + hokkaido, crossings: [0], countries: [kr] + Array(repeating: jp, count: 5))),
            Case(name: "a drive to the airport first", form: .departure,
                 trip: trip(loop(seoul, radiusDeg: 0.2, count: 3) + [incheon] + hokkaido, crossings: [3],
                            countries: [kr, kr, kr, kr] + Array(repeating: jp, count: 5))),
            Case(name: "the departure airport has 12 photographs", form: .departure,
                 trip: trip([incheon] + hokkaido, crossings: [0], photos: [12, 3, 3, 3, 3, 3],
                            countries: [kr] + Array(repeating: jp, count: 5))),
            Case(name: "a short island hop (≈200 km)", form: .departure,
                 trip: trip(loop(barcelona, radiusDeg: 0.15, count: 3) + loop(palma, radiusDeg: 0.25, count: 4),
                            crossings: [2], countries: ["ES", "ES", "ES", "ES", "ES", "ES", "ES"])),
            Case(name: "a long-haul past the flight frame's limit", form: .departure,
                 trip: trip([singapore] + loop(london, radiusDeg: 0.4, count: 5), crossings: [0],
                            countries: ["SG"] + Array(repeating: "GB", count: 5)), drawsTheFlight: false),
            Case(name: "across 180° to an island", form: .departure,
                 trip: trip([incheon] + loop(honolulu, radiusDeg: 0.2, count: 4), crossings: [0],
                            countries: [kr, "US", "US", "US", "US"]), drawsTheFlight: false),
            Case(name: "a long-haul to a country with its own frame", form: .departure,
                 trip: trip([london] + hokkaido, crossings: [0], countries: ["GB"] + Array(repeating: jp, count: 5)),
                 drawsTheFlight: false),
            Case(name: "up to the high Arctic", form: .departure,
                 trip: trip([oslo] + loop(longyearbyen, radiusDeg: 0.15, count: 4), crossings: [0],
                            countries: ["NO", "NO", "NO", "NO", "NO"])),
            Case(name: "a domestic flight in the south", form: .departure,
                 trip: trip([johannesburg] + loop(capeTown, radiusDeg: 0.3, count: 4), crossings: [0],
                            countries: ["ZA", "ZA", "ZA", "ZA", "ZA"])),
            Case(name: "a destination of one photograph", form: .departure,
                 trip: trip(loop(seoul, radiusDeg: 0.2, count: 3) + [incheon, sapporo], crossings: [3],
                            countries: [kr, kr, kr, kr, jp])),
            Case(name: "through a transit airport", form: .departure,
                 trip: trip([london, dubai] + loop(singapore, radiusDeg: 0.1, count: 4), crossings: [0, 1],
                            countries: ["GB", "AE", "SG", "SG", "SG", "SG"])),
            Case(name: "two destinations (multi-region renders type 2)", form: .departure,
                 trip: trip([incheon] + hokkaido + loop(Place(lat: 35.0, lon: 135.75), radiusDeg: 0.3, count: 4),
                            crossings: [0, 5], countries: [kr] + Array(repeating: jp, count: 9))),
            Case(name: "a photograph taken in the air", form: .departure,
                 trip: trip([incheon, Place(lat: 40.0, lon: 133.0)] + hokkaido, crossings: [0, 1],
                            countries: [kr, ""] + Array(repeating: jp, count: 5))),
            Case(name: "the trip is only the flight", form: .departure,
                 trip: trip([incheon, sapporo], crossings: [0], countries: [kr, jp])),
            Case(name: "a crossing confirmed while other legs are unrouted", form: .departure,
                 trip: trip([incheon] + hokkaido, crossings: [0], countries: [kr] + Array(repeating: jp, count: 5),
                            established: false)),
            Case(name: "no stop was named a country", form: .departure,
                 trip: trip([incheon] + hokkaido, crossings: [0]), pass: false)
        ]
    }

    // MARK: - Tests

    func testEveryLocalFilmHoldsEveryInvariant() throws {
        try run(localCases)
    }

    func testEveryFilmWithADepartureHoldsEveryInvariant() throws {
        try run(departureCases)
    }

    private func run(_ cases: [Case]) throws {
        let config = try shipped()
        var failures: [String] = []
        for test in cases {
            var measured = Measured()
            let violations = audit(test, config: config, measured: &measured)
            print(String(
                format: "KAMOME_EXPORT_MATRIX  %-52@ %6.1f s  %5d frames  %4d stations (%.2f/s)  build %.2f s  plan %.2f s",
                test.name as NSString, measured.durationS, measured.frames, measured.stations,
                measured.durationS > 0 ? Double(measured.stations) / measured.durationS : 0,
                measured.buildS, measured.planS
            ))
            failures += violations.map { "\(test.name): \($0)" }
        }
        XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }
}
