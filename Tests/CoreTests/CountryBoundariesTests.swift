import XCTest

@testable import KamomeImportKit

/// **The bundled country outlines** (ADR 2026-09-25), read the way journey
/// discovery reads them: inside an outline, else the nearest within the coast
/// buffer, else no answer.
final class CountryBoundariesTests: XCTestCase {
    private static let countries = CountryBoundaries.bundled()
    /// `discovery.country_coast_buffer_m` as shipped (`ConfigLoaderTests` pins it).
    private let buffer = 3_000.0

    private func country(_ lat: Double, _ lon: Double) throws -> String? {
        try XCTUnwrap(Self.countries, "the outlines ship in KamomeImportKit").country(
            lat: lat, lon: lon, coastBufferM: buffer
        )
    }

    /// **Taiwan and China are two countries, with a border between them**
    /// (Chiu 2026-09-25). The islands a few kilometres off Fujian are Taiwan's:
    /// Kinmen from the admin-0 outline, Lieyu, Wuqiu and Matsu added by name
    /// because the 1:10m layer leaves them out.
    func testTaiwanAndChinaAreTwoCountries() throws {
        let taiwan: [String: [Double]] = [
            "Taipei": [25.04, 121.56], "Kinmen": [24.44, 118.37], "Lieyu": [24.43, 118.24],
            "Wuqiu": [24.99, 119.47], "Nangan, Matsu": [26.155, 119.93], "Beigan, Matsu": [26.22, 119.99],
            "Dongyin, Matsu": [26.37, 120.49], "Penghu": [23.57, 119.58], "Lanyu": [22.05, 121.55],
            "Green Island": [22.66, 121.49], "Xiaoliuqiu": [22.34, 120.37]
        ]
        for (name, position) in taiwan {
            XCTAssertEqual(try country(position[0], position[1]), "TWN", name)
        }
        XCTAssertEqual(try country(26.07, 119.30), "CHN", "Fuzhou")
        XCTAssertEqual(try country(24.53, 118.10), "CHN", "Xiamen")
    }

    /// Natural Earth's `ISO_A2` for Taiwan is "CN-TW"; the file is keyed by
    /// `ADM0_A3`, so no code anywhere in it files Taiwan under China.
    func testNoCountryIsFiledUnderAnother() throws {
        let codes = try XCTUnwrap(Self.countries).countries.map(\.code)
        XCTAssertTrue(codes.contains("TWN"))
        XCTAssertTrue(codes.allSatisfy { $0.count == 3 && !$0.contains("-") }, "\(codes.filter { $0.contains("-") })")
        XCTAssertEqual(Set(codes).count, codes.count, "one entry per country")
    }

    func testNeighboursAcrossTheSea() throws {
        XCTAssertEqual(try country(24.34, 124.16), "JPN", "Ishigaki, on the harbour's coastline")
        XCTAssertEqual(try country(24.465, 122.99), "JPN", "Yonaguni, 110 km from Taiwan")
        XCTAssertEqual(try country(33.50, 126.53), "KOR", "Jeju")
        XCTAssertEqual(try country(25.18, 121.41), "TWN", "Tamsui, at the river mouth")
    }

    /// At sea there is no answer — the detector takes that as no evidence, so a
    /// photograph from the plane or the ferry can neither start nor end a trip abroad.
    func testOpenSeaIsNoCountry() throws {
        XCTAssertNil(try country(29.0, 125.0), "East China Sea")
        XCTAssertNil(try country(24.0, 120.0), "the Taiwan Strait between Penghu and Fujian")
    }

    /// A hole is outside its country: Lesotho, surrounded by South Africa.
    func testAnEnclaveIsItsOwnCountry() throws {
        XCTAssertEqual(try country(-29.31, 27.48), "LSO", "Maseru")
        XCTAssertEqual(try country(-26.20, 28.05), "ZAF", "Johannesburg")
    }

    func testABrokenFileIsRefusedNotMisread() {
        XCTAssertThrowsError(try CountryBoundaries(data: Data("KCB1".utf8)))
        XCTAssertThrowsError(try CountryBoundaries(data: Data("KCB2".utf8) + Data([5, 0, 0, 0])))
    }
}
