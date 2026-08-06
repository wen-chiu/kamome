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

    /// **Changed 2026-08-06 (Chiu): an address is not a destination.** This used
    /// to expect the house number. Landmark → town → nothing is the rule now, so a
    /// `name` that is just its own thoroughfare plus a number falls through to the
    /// town the viewer can actually place.
    func testStreetAddressNameFallsBackToTheTown() {
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
        XCTAssertEqual(name, "龜山區")
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

    /// A `name` equal to a coarse field is still rejected — and now falls to the
    /// town rather than to the street, since streets are no longer candidates.
    func testNameEqualToCoarseFieldFallsBackToTheTown() {
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
        XCTAssertEqual(name, "龜山區")
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

    /// The 2026-07-18 defect, in the form that actually reaches us: `name` is
    /// 臺灣島 while `country` is 台灣 — different strings, so equality never
    /// caught it. A name that embeds its own country is region-scale.
    func testNameEmbeddingItsCountryIsRejectedAcrossCharacterVariants() {
        XCTAssertEqual(
            StopDisplayName.choose(
                name: "臺灣島", locality: "龜山區", administrativeArea: "桃園市", country: "台灣"
            ),
            "龜山區"
        )
    }

    /// The narrow edge of that rule: a POI whose name merely *starts with* the
    /// region's stem must survive, or every night market in Taoyuan disappears.
    func testPoiSharingAStemWithItsRegionSurvives() {
        XCTAssertEqual(
            StopDisplayName.choose(
                name: "桃園觀光夜市", thoroughfare: "民生路", locality: "桃園區",
                administrativeArea: "桃園市", country: "台灣"
            ),
            "桃園觀光夜市"
        )
    }

    /// A landmark beats the town it sits near — the Iceland case that started
    /// this: `name` "Glacier Lagoon" with `locality` 60 km away.
    func testLandmarkBeatsTheNearestTown() {
        XCTAssertEqual(
            StopDisplayName.choose(
                name: "Glacier Lagoon", locality: "Höfn í Hornafirði",
                administrativeArea: "Southern Region", country: "Iceland",
                inlandWater: "Glacier Lagoon", areasOfInterest: ["Vatnajökull National Park", "Iceland"]
            ),
            "Glacier Lagoon"
        )
    }

    /// An Icelandic road number is worse than the town, so it must not win.
    func testRouteNumberNameFallsBackToTheTown() {
        XCTAssertEqual(
            StopDisplayName.choose(
                name: "871", locality: "Vík", administrativeArea: "Southern Region",
                country: "Iceland", areasOfInterest: ["Iceland"]
            ),
            "Vík"
        )
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
