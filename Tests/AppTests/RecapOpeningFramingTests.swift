@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **What the opening establishes, and what that does to the body span**
/// (`Docs/camera-arcs.md` §5, `HANDOFF.md` 2026-08-30 finding 1).
///
/// `RecapDurationPlan.bodySpanM` divides the span of the opening's **first
/// beat** by `target_zoom_ratio`; the pan floor was measured on 2026-08-30 to
/// be ~16 km against an ask of ~274 km, so it never binds and the opening is
/// the only thing that sets how tightly the destination is framed.
///
/// This harness prints that chain — established span, ask, floor, body span —
/// for each candidate `establishing` extent on one fixture, so the framing
/// question is answered with a number instead of an inference.
final class RecapOpeningFramingTests: XCTestCase {
    private func bounds(_ coordinates: [RecapCoordinate]) throws -> RecapBounds {
        let box = try XCTUnwrap(GeoBox.enclosing(coordinates.map { (lat: $0.lat, lon: $0.lon) }))
        return RecapBounds(
            minLat: box.minLat, minLon: box.minLon, maxLat: box.maxLat, maxLon: box.maxLon
        )
    }

    /// The legs after the crossing — the destination's own local journey.
    private func destinationCoordinates(_ trip: RecapTrip) throws -> [RecapCoordinate] {
        let crossingIndex = try XCTUnwrap(
            trip.legs.firstIndex(where: \.isCrossing), "the fixture has no crossing"
        )
        return trip.legs[(crossingIndex + 1)...].flatMap(\.coordinates)
    }

    private func originCoordinates(_ trip: RecapTrip) throws -> [RecapCoordinate] {
        let crossingIndex = try XCTUnwrap(
            trip.legs.firstIndex(where: \.isCrossing), "the fixture has no crossing"
        )
        return trip.legs[..<crossingIndex].flatMap(\.coordinates)
    }

    /// Where the film's body camera actually starts, against where beat 2 frames.
    func testWhereTheOpeningFramesVersusWhereTheBodyStarts() async throws {
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: UnroutableSeaProvider.crossingFixture, baseURL: "",
            reconstructor: UnroutableSeaProvider.forFixture(UnroutableSeaProvider.crossingFixture)
        )
        let line = try XCTUnwrap(LinearTimeline(trip: trip, config: config, establishing: nil))
        let cut = try XCTUnwrap(line.titleCutS)
        let beat2 = line.cameraFrame(atTime: cut + 0.1)
        let body = line.cameraFrame(atTime: line.openingS + 0.5)
        let origin = try XCTUnwrap(trip.route.first)
        let destination = try XCTUnwrap(destinationCoordinates(trip).first)
        print(String(
            format: "KAMOME_OPENING_ANCHOR beat2 is %.0f km from the origin and %.0f km from the destination · "
                + "the body starts %.0f km from the origin · closing zoom travels %.0f km across a %.1f km frame",
            Geo.distanceM(latA: beat2.centerLat, lonA: beat2.centerLon, latB: origin.lat, lonB: origin.lon) / 1000,
            Geo.distanceM(
                latA: beat2.centerLat, lonA: beat2.centerLon, latB: destination.lat, lonB: destination.lon
            ) / 1000,
            Geo.distanceM(latA: body.centerLat, lonA: body.centerLon, latB: origin.lat, lonB: origin.lon) / 1000,
            Geo.distanceM(
                latA: beat2.centerLat, lonA: beat2.centerLon, latB: body.centerLat, lonB: body.centerLon
            ) / 1000,
            beat2.spanM / 1000
        ))
    }

    func testWhatEachEstablishingExtentDoesToTheBodySpan() async throws {
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: UnroutableSeaProvider.crossingFixture, baseURL: "",
            reconstructor: UnroutableSeaProvider.forFixture(UnroutableSeaProvider.crossingFixture)
        )

        let candidates: [(String, RecapBounds?)] = [
            ("nil — WHAT SHIPS", nil),
            ("whole trip bounds", try bounds(trip.route)),
            ("destination segment bounds", try bounds(destinationCoordinates(trip))),
            ("origin segment bounds", try bounds(originCoordinates(trip))),
            // Deliberately WIDER than the trip, to separate two candidate
            // mechanisms: if the established span tracks this, the country beat
            // is a function of the extent; if it does not, it is a function of
            // `union(extent, tripBounds)` and every subset of the trip is the
            // same input.
            ("extent wider than the trip", RecapBounds(
                minLat: 18.0, minLon: 118.0, maxLat: 34.0, maxLon: 136.0
            )),
            ("extent much wider still", RecapBounds(
                minLat: 5.0, minLon: 100.0, maxLat: 50.0, maxLon: 150.0
            ))
        ]

        for (label, establishing) in candidates {
            let line = try XCTUnwrap(
                LinearTimeline(trip: trip, config: config, establishing: establishing),
                "no timeline for \(label)"
            )
            // Sampled through the public accessor the render loop itself uses,
            // so this measures the film rather than the path's internals.
            let established = line.cameraFrame(atTime: 0).spanM
            let body = line.cameraFrame(atTime: min(line.durationS, line.openingS + 1.0)).spanM
            print(String(
                format: "KAMOME_OPENING_FRAMING %-28@ · established %8.1f km · body %8.1f km "
                    + "· ratio %5.2f× · opening %.1fs · film %.1fs",
                label as NSString, established / 1000, body / 1000,
                established / max(body, 1), line.openingS, line.durationS
            ))
        }
    }

    /// **Where the opening's snapshots actually go** — the 151 is asserted in
    /// `Docs/camera-arcs.md` §2 to be "the 5 s of easing", derived from the beat
    /// arithmetic and never measured. This walks the opening frame by frame and
    /// counts *distinct* camera values, which is what the render loop's value
    /// cache keys on, so a held beat costs one however long it is held.
    func testWhereTheOpeningsDistinctCameraValuesAre() async throws {
        for fixture in ["ishigaki-crossing", "miyakojima"] {
            let reconstructor = UnroutableSeaProvider.forFixture(fixture)
            let (trip, config) = try await RecapDemoFilmTests.importedRecap(
                named: fixture, baseURL: "", reconstructor: reconstructor
            )
            let line = try XCTUnwrap(
                LinearTimeline(trip: trip, config: config, establishing: nil), "no timeline"
            )
            let openingFrames = Int((line.openingS * Double(config.fps)).rounded())
            /// A stretch of the opening the camera spends at one framing.
            struct Run { let startS: Double; var endS: Double; let frame: CameraFrame }
            var runs: [Run] = []
            for frame in 0..<max(openingFrames, 1) {
                let time = Double(frame) / Double(config.fps)
                let camera = line.cameraFrame(atTime: time)
                if var last = runs.last, last.frame == camera {
                    last.endS = time
                    runs[runs.count - 1] = last
                } else {
                    runs.append(Run(startS: time, endS: time, frame: camera))
                }
            }
            let distinct = Set(runs.map(\.frame)).count
            print(String(
                format: "KAMOME_OPENING_SPLIT %@ · opening %.2fs (%d frames) · %d distinct camera values",
                fixture, line.openingS, openingFrames, distinct
            ))
            // Runs longer than one frame are the holds; everything else is motion.
            for run in runs where run.endS > run.startS {
                print(String(
                    format: "KAMOME_OPENING_SPLIT   HELD %5.2f–%5.2fs (%4.2fs) at span %8.1f km",
                    run.startS, run.endS, run.endS - run.startS, run.frame.spanM / 1000
                ))
            }
            let moving = runs.filter { $0.endS == $0.startS }.count
            print(String(
                format: "KAMOME_OPENING_SPLIT   %d held run(s) · %d moving frame(s) — "
                    + "the moving frames are the opening's snapshot bill",
                runs.count - moving, moving
            ))
            // **The cost model's own premise, asserted rather than described.**
            // `Docs/camera-arcs.md` §2 rests on "holding is free; only moving
            // costs" — one camera value per held beat, however long it is held.
            // If a beat ever stopped collapsing to a single value, the opening's
            // budget would silently multiply and every figure in §2 and in
            // `Docs/handoff-crop-scaling.md` would be wrong with nothing red.
            let held = runs.filter { $0.endS > $0.startS }
            XCTAssertEqual(
                held.count, Set(held.map(\.frame)).count,
                "each held beat must be exactly one camera value — two would mean the "
                    + "beat is drifting and the opening costs more than §2 says"
            )
            XCTAssertGreaterThanOrEqual(
                held.count, 1, "an opening with no held beat has nothing for a viewer to read"
            )
        }
    }
}
