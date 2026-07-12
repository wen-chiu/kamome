import KamomeTrackingEngine
import XCTest

final class SamplingPolicyTests: XCTestCase {
    func testAdaptiveTableFollowsSpecAndVehiclePresets() throws {
        let config = try GPXReplay.loadConfig()

        // §2.3: fast automotive → coarse filter; slow → fine; walking → finest.
        let fast = SamplingPolicyTable.policy(state: .recording, mode: .drive, speedKmh: 80, vehicle: .car, config: config)
        XCTAssertEqual(fast?.distanceFilterM, 50)
        let slow = SamplingPolicyTable.policy(state: .recording, mode: .drive, speedKmh: 10, vehicle: .car, config: config)
        XCTAssertEqual(slow?.distanceFilterM, 20)
        let walk = SamplingPolicyTable.policy(state: .recording, mode: .walk, speedKmh: 5, vehicle: .car, config: config)
        XCTAssertEqual(walk?.distanceFilterM, 10)

        // §1.7: scooter preset keeps higher fidelity at speed.
        let scooter = SamplingPolicyTable.policy(
            state: .recording, mode: .scooter, speedKmh: 50, vehicle: .scooter, config: config
        )
        XCTAssertEqual(scooter?.distanceFilterM, 30)

        // §2.3: dwell-paused runs on region monitoring — GPS off.
        let paused = SamplingPolicyTable.policy(state: .dwellPaused, mode: .drive, speedKmh: 0, vehicle: .car, config: config)
        XCTAssertNil(paused)
    }
}
