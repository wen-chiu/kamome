@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **The opening must hand over to the body camera without a jump** (2026-08-08).
///
/// `CameraPath` frames the opening's last wide beat on where the follow camera
/// will have settled, and decides whether the closing zoom is worth playing by
/// comparing against that same frame. Neither can ask the simulation: the track
/// is built after the opening plan, because it needs the journey timeline the
/// plan produces. So `FollowCamera.restingFrame` states the simulation's fixed
/// point in closed form, and this is what keeps the two honest.
///
/// The failure it exists to prevent is specific. `bodyFrame` used to predict the
/// handoff as the route's own framing — the world clamp on the first point —
/// which is only where the dolly *starts*. The spring then ran for the whole
/// opening (the vehicle waits at the route's start, so it is stationary, and
/// stationary is not parked) and settled 25 km away on New Zealand. Nothing
/// measured the gap, so the prediction stayed wrong and the opening pre-panned
/// across the country to a place the camera was not going to be.
final class FollowCameraRestingFrameTests: XCTestCase {
    private static let fixtures = [
        "margaret-river", "miyakojima", "iceland", "finland", "new-zealand", "nz-real"
    ]

    /// The predicted resting frame must be where the simulated track actually is
    /// at the handoff. Tolerance is a fraction of the frame rather than an
    /// absolute distance — what matters is how much of the picture it represents,
    /// and the spans here range from 7.5 km to 91 km.
    ///
    /// The residual is the projection's reference latitude: `FollowCamera.track`
    /// scales longitude about the mean of the *sampled* subject positions, which
    /// depends on pacing and is unknowable before the timeline exists, so the
    /// closed form uses the route bounds' mid-latitude. That is a cosine
    /// difference across one trip's latitude range — metres, not kilometres.
    func testPredictedRestingFrameMatchesTheSimulatedTrack() async throws {
        for fixture in Self.fixtures {
            let (trip, config) = try await RecapDemoFilmTests.importedRecap(named: fixture, baseURL: "")
            let box = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
            let line = try XCTUnwrap(LinearTimeline(
                trip: trip, config: config,
                establishing: RecapBounds(
                    minLat: box.minLat, minLon: box.minLon, maxLat: box.maxLat, maxLon: box.maxLon
                )
            ))
            let path = line.path
            let route = trip.route.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
            let predicted = FollowCamera.restingFrame(
                subject: route[0], routeBounds: CameraPath.bounds(of: route),
                spanM: path.bodySpanM, config: config
            )
            let actual = path.cameraFrame(atTime: path.journeyStartS)
            let gapM = Self.metres(
                predicted.centerLat, predicted.centerLon, actual.centerLat, actual.centerLon
            )
            let share = gapM / path.bodySpanM
            print(String(
                format: "KAMOME_RESTING %-16@ gap %6.0f m of a %6.0f m frame (%.3f%%)",
                fixture as NSString, gapM, path.bodySpanM, share * 100))
            XCTAssertLessThan(
                share, 0.01,
                "\(fixture): the opening is framed \(Int(gapM)) m from where the body camera "
                    + "actually settles — the handoff will show as a jump"
            )
        }
    }

    /// The seam itself, measured the way the eye meets it: the last frame of the
    /// opening against the first frame of the body. Complementary to the
    /// prediction test above — that one checks a value, this one checks the film.
    ///
    /// A separate assertion because the closing zoom can hide a bad prediction:
    /// when it plays, it ends exactly on the live track and the seam is exact
    /// however wrong the prediction was. It is when the zoom is *collapsed* —
    /// which a wrong prediction makes more likely — that the error becomes a cut.
    func testTheOpeningHandsOverWithoutAJump() async throws {
        for fixture in Self.fixtures {
            let (trip, config) = try await RecapDemoFilmTests.importedRecap(named: fixture, baseURL: "")
            let box = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
            let line = try XCTUnwrap(LinearTimeline(
                trip: trip, config: config,
                establishing: RecapBounds(
                    minLat: box.minLat, minLon: box.minLon, maxLat: box.maxLat, maxLon: box.maxLon
                )
            ))
            let path = line.path
            let handover = path.journeyStartS
            let before = path.cameraFrame(atTime: handover - 1.0 / Double(config.fps))
            let after = path.cameraFrame(atTime: handover)
            let movedM = Self.metres(
                before.centerLat, before.centerLon, after.centerLat, after.centerLon
            )
            let share = movedM / after.spanM
            print(String(
                format: "KAMOME_SEAM    %-16@ moved %6.0f m across a %6.0f m frame (%.1f%%)",
                fixture as NSString, movedM, after.spanM, share * 100))
            XCTAssertLessThan(
                share, 0.05,
                "\(fixture): the frame moved \(Int(movedM)) m in the single frame where the "
                    + "opening becomes the body camera"
            )
        }
    }

    private static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let haversine = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}
