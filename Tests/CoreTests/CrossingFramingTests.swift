import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **Which type-2 films draw their flight** (`CrossingFraming`, Chiu 2026-09-01).
///
/// Every row here is a measurement from `LongHaulFrameProbeTests` on 2026-09-01,
/// turned into an assertion so the policy cannot drift away from what was
/// actually rendered. The probe needs the network and is env-gated; this does
/// not, and runs on every CI job.
final class CrossingFramingTests: XCTestCase {
    /// Repo-root `Config/TrackingConfig.json`, located relative to this source
    /// file so the test works in both `swift test` and xcodebuild runs — the
    /// same helper `ConfigLoaderTests` uses.
    private func exportConfig() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    /// Public city coordinates, never a fixture (`CLAUDE.md` §0).
    private let taipei = RecapCoordinate(lat: 25.0330, lon: 121.5654)
    private let ishigaki = RecapCoordinate(lat: 24.3448, lon: 124.1572)
    private let tokyo = RecapCoordinate(lat: 35.6762, lon: 139.6503)
    private let sydney = RecapCoordinate(lat: -33.8688, lon: 151.2093)
    private let helsinki = RecapCoordinate(lat: 60.1699, lon: 24.9384)
    private let reykjavik = RecapCoordinate(lat: 64.1466, lon: -21.9426)

    private func verdict(_ destination: RecapCoordinate) throws -> CrossingFraming.Verdict {
        CrossingFraming.verdict(
            from: taipei, to: destination, config: try exportConfig(),
            substrateMaxLongitudeDeg: MapKitSnapshotProvider.maxLongitudeSpanDeg
        )
    }

    /// The three that rendered, in both appearances, with both cities labelled.
    func testTheDistancesThatRenderedDrawTheirFlight() throws {
        XCTAssertEqual(try verdict(ishigaki), .drawTheFlight, "2.6 degrees")
        XCTAssertEqual(try verdict(tokyo), .drawTheFlight, "18.1 degrees")
        XCTAssertEqual(
            try verdict(sydney), .drawTheFlight,
            "29.6 degrees and 7,206 km — the row that proves the threshold is not a distance"
        )
    }

    /// **Iceland, the project's most-judged trip, has no frame.** If this ever
    /// returns `.drawTheFlight`, the film is asking for a picture that does not
    /// exist.
    func testIcelandFallsBackToTheFrozenCard() throws {
        guard case .frozenCard = try verdict(reykjavik) else {
            return XCTFail("Taipei-Reykjavik is 143.5 degrees apart and cannot be framed at any padding")
        }
    }

    /// Finland frames only with the padding thrown away, and that picture has
    /// neither city labelled and both 59 px from opposite bezels.
    func testFinlandIsPastThePolicyEvenThoughAFrameOfSortsExists() throws {
        XCTAssertEqual(try verdict(helsinki), .frozenCard(.beyondFilmPolicy), "96.6 degrees")
    }

    /// **The threshold is degrees, and this is the test that says so.** A pair
    /// 7,206 km apart draws its flight and one 12,313 km apart does not — but
    /// swap the axis and the distances stop predicting anything. Two synthetic
    /// pairs at the same latitude, the same ground distance apart, one running
    /// north–south and one east–west.
    func testTheSameDistanceAnswersDifferentlyNorthSouthThanEastWest() throws {
        let config = try exportConfig()
        let origin = RecapCoordinate(lat: 0, lon: 0)
        // 80 degrees of latitude is ~8,900 km and no degrees of longitude.
        let northSouth = RecapCoordinate(lat: 80, lon: 0)
        // ~8,900 km due east at the equator is 80 degrees of longitude.
        let eastWest = RecapCoordinate(lat: 0, lon: 80)
        XCTAssertEqual(
            CrossingFraming.verdict(
                from: origin, to: northSouth, config: config,
                substrateMaxLongitudeDeg: MapKitSnapshotProvider.maxLongitudeSpanDeg
            ),
            .drawTheFlight,
            "a north-south pair spans no longitude and frames at any distance"
        )
        XCTAssertEqual(
            CrossingFraming.verdict(
                from: origin, to: eastWest, config: config,
                substrateMaxLongitudeDeg: MapKitSnapshotProvider.maxLongitudeSpanDeg
            ),
            .frozenCard(.beyondFilmPolicy),
            "the same ground distance east-west is 80 degrees and is refused"
        )
    }

    /// The policy must sit **under** the substrate's wall, or the capability
    /// layer is the only thing preventing a frame nobody can draw — which is the
    /// arrangement this design exists to avoid.
    func testTheFilmPolicyStaysInsideWhatTheSubstrateCanDraw() throws {
        XCTAssertLessThan(
            try exportConfig().crossingFlightMaxLongitudeDeg,
            MapKitSnapshotProvider.maxLongitudeSpanDeg,
            "a policy at or past the measured wall leaves the film with no headroom at all"
        )
    }

    /// A frame that is within the longitude limits can still be taller than the
    /// planet, because the portrait aspect multiplies its height by 1.778. The
    /// two limits are independent and both are checked.
    func testTheAspectLimitIsCheckedSeparatelyFromTheLongitudeOne() throws {
        // A pair exactly **at** the shipped policy, at the equator, where a
        // degree of longitude is at its widest: 70 degrees is 7,792 km, and
        // padded by 1.5 and stretched by the 9:16 aspect it is 20,782 km tall —
        // 186.7 degrees, past the poles. It passes both longitude checks and only
        // the aspect check can refuse it, which is why there are three.
        let verdict = CrossingFraming.verdict(
            from: RecapCoordinate(lat: 0, lon: 0), to: RecapCoordinate(lat: 0, lon: 70),
            config: try exportConfig(),
            substrateMaxLongitudeDeg: MapKitSnapshotProvider.maxLongitudeSpanDeg
        )
        XCTAssertEqual(verdict, .frozenCard(.tallerThanThePlanet))
    }
}
