import Foundation
@testable import KamomeExportEngine
import XCTest

/// A failed catalogue load must not outlive the call that failed (#121).
///
/// The 2026-09-16 occurrence drew the badge for every subject in one process,
/// with the bundle found, and a retry drew the car. The store used to cache the
/// failure — an empty manifest, nil artwork — so one transient miss held for the
/// whole process. These tests make the first read fail and assert the second
/// one recovers.
final class VehicleCatalogRetryTests: XCTestCase {
    /// A bundle source that is absent for its first `failures` calls, then real.
    private final class FlakyBundle: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        init(failures: Int) { remaining = failures }
        func next() -> Bundle? {
            lock.withLock {
                if remaining > 0 {
                    remaining -= 1
                    return nil
                }
                return VehicleResourceBundle.resolved
            }
        }
    }

    func testTheRealBundleResolvesHere() {
        XCTAssertNotNil(VehicleResourceBundle.resolved, "these tests need the shipped resource bundle")
    }

    func testAManifestThatFailedOnceLoadsOnTheNextLookup() {
        let source = FlakyBundle(failures: 1)
        let store = VehicleCatalog.Store(bundle: source.next)

        XCTAssertTrue(store.subjects.isEmpty, "the first read has no bundle")
        XCTAssertFalse(store.subjects.isEmpty, "the failure was cached — every later lookup would miss")
    }

    func testAnArtworkMissIsNotCached() {
        // Call 1 reads the manifest from the real bundle. Call 2, the first
        // artwork read, gets a bundle that opens but holds no drawings — the
        // decode itself misses, which is the branch that used to be cached.
        // Call 3, the retry, gets the real bundle again.
        let calls = Counter()
        let emptyBundle = Bundle(for: Self.self)
        let store = VehicleCatalog.Store {
            calls.increment()
            return calls.value == 2 ? emptyBundle : VehicleResourceBundle.resolved
        }
        XCTAssertNil(store.artwork(id: "car-red"), "the first artwork read finds no drawings")
        XCTAssertNotNil(
            store.artwork(id: "car-red"),
            "the miss was cached — the film would draw the badge until relaunch"
        )
    }

    func testEachManifestFailureNamesItsStep() {
        XCTAssertEqual(failure(VehicleCatalog.Store.decodeManifest(bundle: nil)), .noBundle)
        // The test bundle opens but carries no Vehicles/vehicles.json.
        XCTAssertEqual(failure(VehicleCatalog.Store.decodeManifest(bundle: Bundle(for: Self.self))), .noFile)
        XCTAssertNil(failure(VehicleCatalog.Store.decodeManifest(bundle: VehicleResourceBundle.resolved)))
    }

    private func failure(
        _ result: Result<[VehicleSubject], VehicleCatalog.Store.ManifestFailure>
    ) -> VehicleCatalog.Store.ManifestFailure? {
        if case let .failure(step) = result { return step }
        return nil
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }
}
