import XCTest

@testable import KamomeImportKit

/// **Journey discovery, as a pure function** (2026-09-17). Home is guessed,
/// away photographs are cut into journeys by time, and the keys are stable.
final class JourneyDetectorTests: XCTestCase {
    // ~55 km cells, 40 km "away", a two-day gap splits, eight photographs make a journey.
    private let config = JourneyDetectionConfig(
        homeCellDeg: 0.5, awayRadiusM: 40_000, journeyGapS: 2 * 86_400, minPhotos: 8,
        homecomingMinJumpM: 100_000, countryCoastBufferM: 3_000
    )

    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double, favorite: Bool = false) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon, isFavorite: favorite)
    }

    private let week = 7.0 * 86_400

    /// One photograph a week at home for a year — invented suburb coordinates —
    /// taken the evening before each week mark, where every trip here departs.
    /// Never *at* the mark: since a photograph at home ends a journey (R1), one
    /// sharing the trip's first second would be ordered by asset id alone, and
    /// "at home and in Helsinki at once" would decide the test by the alphabet.
    private func homeYear() -> [ImportPhoto] {
        (0..<52).map { photo("home-\($0)", Double($0) * week - 3 * 3_600, 25.04, 121.56) }
    }

    /// `count` photographs half an hour apart, starting at `start`, at one place.
    private func burst(_ prefix: String, start: Double, count: Int, lat: Double, lon: Double) -> [ImportPhoto] {
        (0..<count).map { photo("\(prefix)-\($0)", start + Double($0) * 1_800, lat + Double($0 % 3) * 0.001, lon) }
    }

    func testHomeIsTheCellPhotographedAcrossTheMostWeeks() {
        // A fortnight abroad out-shoots a year at home: 40 photographs in two
        // weeks against 52 in fifty-two. Home must still be home.
        let abroad = burst("jp", start: 10 * week, count: 40, lat: 35.68, lon: 139.65)
        let detection = JourneyDetector.detect(photos: homeYear() + abroad, config: config)

        let home = detection.home
        XCTAssertNotNil(home)
        XCTAssertEqual(home?.lat ?? 0, 25.04, accuracy: 0.01)
        XCTAssertEqual(home?.lon ?? 0, 121.56, accuracy: 0.01)
        XCTAssertEqual(home?.weekCount, 52)
    }

    func testAwayPhotographsBecomeJourneysSplitByTheGap() {
        let japan = burst("jp", start: 10 * week, count: 12, lat: 35.68, lon: 139.65)
            + burst("kyoto", start: 10 * week + 2 * 86_400, count: 6, lat: 35.01, lon: 135.77)
        let finland = burst("fi", start: 30 * week, count: 9, lat: 60.17, lon: 24.94)
        let detection = JourneyDetector.detect(photos: homeYear() + japan + finland, config: config)

        XCTAssertEqual(detection.journeys.count, 2)
        // Newest first.
        XCTAssertEqual(detection.journeys[0].photoCount, 9, "Finland")
        XCTAssertEqual(detection.journeys[1].photoCount, 18, "Tokyo and Kyoto, two days apart, are one journey")
        XCTAssertEqual(detection.journeys[1].startedAt, 10 * week)
        XCTAssertGreaterThan(detection.journeys[1].extentM, 300_000, "Tokyo → Kyoto ranges across the country")
        XCTAssertLessThan(detection.journeys[0].extentM, 1_000, "one city stays one place")
    }

    func testTooFewAwayPhotographsAreNotAJourney() {
        let dayTrip = burst("day", start: 20 * week, count: 7, lat: 24.50, lon: 121.56) // 60 km south
        let detection = JourneyDetector.detect(photos: homeYear() + dayTrip, config: config)
        XCTAssertTrue(detection.journeys.isEmpty, "seven photographs are under the eight-photo floor")
    }

    func testPhotographsNearHomeNeverJoinAJourney() {
        // A trip, then a photograph at home the same evening — inside the gap,
        // but not away, so it stays out of the journey.
        let trip = burst("nz", start: 20 * week, count: 10, lat: -45.03, lon: 168.66)
        let atHome = photo("home-evening", 20 * week + 10 * 1_800 + 3_600, 25.04, 121.56)
        let detection = JourneyDetector.detect(photos: homeYear() + trip + [atHome], config: config)

        XCTAssertEqual(detection.journeys.count, 1)
        XCTAssertFalse(detection.journeys[0].photos.contains { $0.assetId == "home-evening" })
    }

    /// **R1 (Chiu 2026-09-25): coming home ends a journey.** The Japan import:
    /// home again on the evening of the flight, Yilan (≈50 km, so away) the next
    /// afternoon — well inside the two-day gap. Before R1 the home photograph was
    /// dropped before cutting and the two trips were one.
    func testComingHomeEndsAJourney() {
        let start = 10 * week + 3_600
        let japan = burst("jp", start: start, count: 12, lat: 35.68, lon: 139.65)
        let atHome = photo("home-evening", start + 12 * 1_800, 25.04, 121.56)
        let yilan = burst("yilan", start: start + 86_400, count: 10, lat: 24.60, lon: 121.66)
        let detection = JourneyDetector.detect(photos: homeYear() + japan + [atHome] + yilan, config: config)

        XCTAssertEqual(detection.journeys.map(\.photoCount), [10, 12], "Yilan, then Japan — two journeys")
    }

    /// R1 alone, with no country outlines: with no photograph at home in
    /// between, only the gap can cut, and a trip under two days after the last
    /// stays joined. The country rule below is what separates those.
    func testWithoutAPhotographAtHomeOnlyTheGapCuts() {
        let start = 10 * week + 3_600
        let japan = burst("jp", start: start, count: 12, lat: 35.68, lon: 139.65)
        let yilan = burst("yilan", start: start + 86_400, count: 10, lat: 24.60, lon: 121.66)
        let detection = JourneyDetector.detect(photos: homeYear() + japan + yilan, config: config)

        XCTAssertEqual(detection.journeys.map(\.photoCount), [22])
    }

    // MARK: - The country rule (ADR 2026-09-25)

    private static let countries = CountryBoundaries.bundled()

    private func detect(_ photos: [ImportPhoto]) throws -> JourneyDetection {
        let countries = try XCTUnwrap(Self.countries, "the outlines ship in KamomeImportKit")
        return JourneyDetector.detect(photos: photos, config: config, countries: countries)
    }

    /// The Japan import, as it happened: nobody photographed home between the
    /// flight back and Yilan, so R1 had nothing to cut on. Back in the home
    /// country after Japan ends the journey. The photograph from the plane is at
    /// sea and decides nothing.
    func testFlyingBackIntoTheHomeCountryEndsAJourney() throws {
        let start = 10 * week
        let japan = burst("jp", start: start, count: 12, lat: 35.68, lon: 139.65)
        let plane = photo("plane", start + 12 * 1_800, 29.0, 125.0)
        let yilan = burst("yilan", start: start + 86_400, count: 10, lat: 24.60, lon: 121.66)
        let detection = try detect(homeYear() + japan + [plane] + yilan)

        XCTAssertEqual(detection.journeys.map(\.photoCount), [10, 13], "Yilan, then Japan with the plane photo")
    }

    /// Leaving the home country does not cut: Yilan, then Japan, is one trip.
    func testLeavingTheHomeCountryDoesNot() throws {
        let start = 10 * week
        let yilan = burst("yilan", start: start, count: 10, lat: 24.60, lon: 121.66)
        let japan = burst("jp", start: start + 86_400, count: 12, lat: 35.68, lon: 139.65)
        XCTAssertEqual(try detect(homeYear() + yilan + japan).journeys.map(\.photoCount), [22])
    }

    /// **Kinmen is Taiwan** (Chiu 2026-09-25): two kilometres off Xiamen, and
    /// still home country. Kinmen, then Yilan, is a trip that never left.
    func testKinmenIsTheHomeCountryNotAbroad() throws {
        let start = 10 * week
        let kinmen = burst("kinmen", start: start, count: 10, lat: 24.44, lon: 118.37)
        let yilan = burst("yilan", start: start + 86_400, count: 10, lat: 24.60, lon: 121.66)
        XCTAssertEqual(try detect(homeYear() + kinmen + yilan).journeys.map(\.photoCount), [20])
    }

    /// A drive back over a land border is not a homecoming: Paris home, Geneva,
    /// then Annecy 35 km away in France, then on to Italy — one trip. The step
    /// home is under `homecomingMinJumpM`.
    func testADriveBackOverALandBorderDoesNotCut() throws {
        let home = (0..<52).map { photo("home-\($0)", Double($0) * week - 3 * 3_600, 48.86, 2.35) }
        let start = 10 * week
        let geneva = burst("geneva", start: start, count: 8, lat: 46.20, lon: 6.14)
        let annecy = burst("annecy", start: start + 86_400, count: 8, lat: 45.90, lon: 6.13)
        let turin = burst("turin", start: start + 2 * 86_400, count: 8, lat: 45.07, lon: 7.69)
        XCTAssertEqual(try detect(home + geneva + annecy + turin).journeys.map(\.photoCount), [24])
    }

    /// Without the outlines the rule is off, and detection is what it was.
    func testWithoutOutlinesTheCountryRuleIsOff() {
        let start = 10 * week
        let japan = burst("jp", start: start, count: 12, lat: 35.68, lon: 139.65)
        let yilan = burst("yilan", start: start + 86_400, count: 10, lat: 24.60, lon: 121.66)
        let detection = JourneyDetector.detect(photos: homeYear() + japan + yilan, config: config)
        XCTAssertEqual(detection.journeys.map(\.photoCount), [22])
    }

    /// A homecoming makes two journeys on one day possible; their keys must
    /// still differ, and the first keeps the bare key stored trips were made with.
    func testTwoJourneysStartingOnOneDayHaveDistinctKeys() {
        let morning = 20 * week + 3_600
        let first = burst("am", start: morning, count: 8, lat: 24.50, lon: 121.56)
        let lunch = photo("home-lunch", morning + 8 * 1_800, 25.04, 121.56)
        let second = burst("pm", start: morning + 9 * 1_800, count: 8, lat: 24.50, lon: 121.56)
        let detection = JourneyDetector.detect(photos: homeYear() + first + [lunch] + second, config: config)

        let base = JourneyDetector.key(startedAt: morning)
        XCTAssertEqual(detection.journeys.map(\.key), ["\(base)-2", base], "newest first")
    }

    /// The key is the journey's first UTC day, so adding photographs to the
    /// library later — inside the journey — does not rename it, and the trip
    /// made from it is found again.
    func testTheKeyIsStableWhenLaterPhotographsAreAdded() {
        let trip = burst("it", start: 40 * week, count: 10, lat: 41.90, lon: 12.50)
        let before = JourneyDetector.detect(photos: homeYear() + trip, config: config)
        let more = burst("it-more", start: 40 * week + 86_400, count: 5, lat: 43.77, lon: 11.26)
        let after = JourneyDetector.detect(photos: homeYear() + trip + more, config: config)

        XCTAssertEqual(before.journeys.map(\.key), after.journeys.map(\.key))
        XCTAssertEqual(after.journeys[0].photoCount, 15)
        XCTAssertEqual(before.journeys[0].key, JourneyDetector.key(startedAt: 40 * week))
    }

    func testAnEmptyLibraryHasNoHomeAndNoJourneys() {
        let detection = JourneyDetector.detect(photos: [], config: config)
        XCTAssertNil(detection.home)
        XCTAssertTrue(detection.journeys.isEmpty)
    }

    /// Deterministic: shuffled input, same answer.
    func testTheAnswerDoesNotDependOnInputOrder() {
        let photos = homeYear()
            + burst("jp", start: 10 * week, count: 12, lat: 35.68, lon: 139.65)
            + burst("fi", start: 30 * week, count: 9, lat: 60.17, lon: 24.94)
        let ordered = JourneyDetector.detect(photos: photos, config: config)
        let shuffled = JourneyDetector.detect(photos: photos.reversed(), config: config)
        XCTAssertEqual(ordered, shuffled)
    }
}
