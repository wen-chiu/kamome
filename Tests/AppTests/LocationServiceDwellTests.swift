import CoreLocation
@testable import Kamome
import XCTest

/// §2.3: on dwell the GPS pauses and a region exit resumes tracking. Region
/// events require Always authorization (and hardware support) — anything less
/// must keep GPS on instead, or the first dwell would strand the trip waiting
/// for an event that can never arrive.
final class LocationServiceDwellTests: XCTestCase {
    func testRegionMonitoringOnlyWithAlwaysAuthorizationAndSupport() {
        XCTAssertEqual(
            LocationService.dwellPausePlan(authorization: .authorizedAlways, regionMonitoringAvailable: true),
            .regionMonitoring
        )
        XCTAssertEqual(
            LocationService.dwellPausePlan(authorization: .authorizedWhenInUse, regionMonitoringAvailable: true),
            .gpsFallback
        )
        XCTAssertEqual(
            LocationService.dwellPausePlan(authorization: .notDetermined, regionMonitoringAvailable: true),
            .gpsFallback
        )
        XCTAssertEqual(
            LocationService.dwellPausePlan(authorization: .denied, regionMonitoringAvailable: true),
            .gpsFallback
        )
        XCTAssertEqual(
            LocationService.dwellPausePlan(authorization: .authorizedAlways, regionMonitoringAvailable: false),
            .gpsFallback
        )
    }
}
