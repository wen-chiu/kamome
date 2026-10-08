@testable import Kamome
import UIKit
import XCTest

/// #245: the database is never opened while the phone is locked since power-on,
/// and is opened exactly once when it can be read.
@MainActor
final class ProtectedDataLaunchTests: XCTestCase {
    private final class Opened {}

    private var opens = 0
    private var available = false
    private let center = NotificationCenter()

    private func makeLaunch() -> ProtectedDataLaunch<Opened> {
        ProtectedDataLaunch(isAvailable: { self.available }, center: center, open: {
            self.opens += 1
            return Opened()
        })
    }

    func testAnUnlockedLaunchOpensAtOnce() {
        available = true
        let launch = makeLaunch()
        XCTAssertNotNil(launch.value)
        XCTAssertEqual(opens, 1)
    }

    func testALockedLaunchOpensNothingUntilTheFirstUnlock() {
        let launch = makeLaunch()
        XCTAssertNil(launch.value)
        XCTAssertEqual(opens, 0, "opening before the first unlock is the crash #245 removes")

        available = true
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        XCTAssertNotNil(launch.value)
        XCTAssertEqual(opens, 1)
    }

    func testBecomingActiveOpensIfTheUnlockNoticeWasMissed() {
        let launch = makeLaunch()
        available = true
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertNotNil(launch.value)
    }

    func testANoticeWhileStillLockedOpensNothing() {
        let launch = makeLaunch()
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertNil(launch.value)
        XCTAssertEqual(opens, 0)
    }

    func testItOpensOnceHoweverManyNoticesArrive() {
        let launch = makeLaunch()
        available = true
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        XCTAssertNotNil(launch.value)
        XCTAssertEqual(opens, 1)
    }
}
