import KamomeTripComposer
import XCTest

/// §4.2 stop naming. The island case reproduces the 2026-07-18 drive, where
/// an urban Taoyuan stop was named "臺灣島".
final class StopDisplayNameTests: XCTestCase {
    func testIslandScaleFeatureNameFallsBackToDistrict() {
        let name = StopDisplayName.choose(
            name: "臺灣島",
            thoroughfare: nil,
            subLocality: nil,
            locality: "龜山區",
            administrativeArea: "桃園市",
            country: "台灣",
            inlandWater: nil,
            ocean: nil
        )
        XCTAssertEqual(name, "龜山區")
    }

    func testStreetAddressNameIsTrustedWithAddressContext() {
        let name = StopDisplayName.choose(
            name: "文化三路一段100號",
            thoroughfare: "文化三路一段",
            subLocality: "樂善里",
            locality: "龜山區",
            administrativeArea: "桃園市",
            country: "台灣",
            inlandWater: nil,
            ocean: nil
        )
        XCTAssertEqual(name, "文化三路一段100號")
    }

    func testPoiNameIsTrustedWithAddressContext() {
        let name = StopDisplayName.choose(
            name: "桃園觀光夜市",
            thoroughfare: "民生路",
            subLocality: nil,
            locality: "桃園區",
            administrativeArea: "桃園市",
            country: "台灣",
            inlandWater: nil,
            ocean: nil
        )
        XCTAssertEqual(name, "桃園觀光夜市")
    }

    func testNameEqualToCoarseFieldIsRejectedEvenWithContext() {
        let name = StopDisplayName.choose(
            name: "桃園市",
            thoroughfare: "文化三路一段",
            subLocality: nil,
            locality: "龜山區",
            administrativeArea: "桃園市",
            country: "台灣",
            inlandWater: nil,
            ocean: nil
        )
        XCTAssertEqual(name, "文化三路一段")
    }

    func testRemoteFeatureNameIsLastResort() {
        let name = StopDisplayName.choose(
            name: "龜山島",
            thoroughfare: nil,
            subLocality: nil,
            locality: nil,
            administrativeArea: nil,
            country: nil,
            inlandWater: nil,
            ocean: nil
        )
        XCTAssertEqual(name, "龜山島")
    }

    func testAllNilYieldsNil() {
        XCTAssertNil(
            StopDisplayName.choose(
                name: nil, thoroughfare: nil, subLocality: nil, locality: nil,
                administrativeArea: nil, country: nil, inlandWater: nil, ocean: nil
            )
        )
    }
}
