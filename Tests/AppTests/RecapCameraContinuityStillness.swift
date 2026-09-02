@testable import Kamome
@testable import KamomeExportEngine
import XCTest

/// **The two beats that may not move**, split out of `RecapCameraContinuityTests`
/// on 2026-09-02 to keep both files inside the size budget.
///
/// Both follow one rule, and it is the rule that separates a gate from an
/// exemption: **assert that there is no motion to be continuous with, never
/// forgive a window.** The continuity scan cannot stand in for either — a slow
/// drift keeps 99% ground overlap frame to frame and passes everything, while
/// being exactly what these beats must not do.
extension RecapCameraContinuityTests {
    /// **The flight beat may not move** (Chiu 2026-09-01: "the plane and its
    /// trail move, the camera does not").
    ///
    /// Same shape as `assertTheCardBeatIsStill`, and the same reason: this is the
    /// one beat in the film whose whole point is that the camera is parked, so it
    /// is asserted rather than assumed. The continuity scan alone could not catch
    /// a drift here — a slow pan keeps 99% overlap frame to frame and passes
    /// everything, while being exactly the thing this beat must not do.
    ///
    /// It also pins the beat's *extent*: the camera must still be parked at the
    /// instant the aircraft lands. An earlier build closed the camera while the
    /// sprite was still crossing, and `CameraPath.confine` chased the subject 24 km
    /// in a single snapshot step (31 violations). That is not a continuity bug
    /// this catches by luck; it is the defect this assertion names.
    func assertTheFlightBeatIsStill(_ line: LinearTimeline, fixture: String, fps: Int) {
        guard line.opensOnTheFlight, let arc = line.path.arcWindowsS.first else { return }
        let step = 1.0 / Double(fps)
        let parked = line.cameraFrame(atTime: 0)
        // Up to the landing: the arc's own hold, which ends when the crossing beat
        // does. Read off the beat rather than assumed to be the arc's midpoint.
        let landing = line.path.crossingBeatWindowsS.first?.upperBound ?? arc.lowerBound
        var moved = 0
        for frame in 0...max(Int((landing * Double(fps)).rounded(.down)), 0)
        where Self.groundOverlap(parked, line.cameraFrame(atTime: Double(frame) * step)) < 1 - 1e-9 {
            moved += 1
        }
        XCTAssertEqual(
            moved, 0,
            "\(fixture): the flight beat moved on \(moved) frames before the aircraft landed at "
                + "\(landing)s — a still camera is the whole of this beat, and a drift here is a "
                + "violation, not a tolerance"
        )
    }
}
