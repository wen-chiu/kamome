@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **One built film, the way the shipped app builds it** — offline, `nil`
/// establishing extent, content-derived pacing.
///
/// Lifted out of `RecapJourneyCardTests` on 2026-09-05, when a second class
/// needed the same three values. Sharing it rather than copying it is the point:
/// the settings below are what make an assertion about a type-2 film mean
/// anything, and two copies of them drift.
struct TypeTwoFilm {
    static let crossing = UnroutableSeaProvider.longHaulFixture
    /// Pinned, because `Locale.current` is a property of the machine and the
    /// card's second line is localized. Two desks must assert the same card.
    static let locale = Locale(identifier: "en_US")

    let line: LinearTimeline
    let trip: RecapTrip
    let config: TrackingConfig.Export

    /// ⚠️ **Offline, always** (`baseURL: ""` + `UnroutableSeaProvider`), the same
    /// way the continuity gate runs. Routed live, a crossing fixture's flight is a
    /// road, no arc is built, and the assertions measure a type-1 film while
    /// looking like they measured a type-2 one.
    static func make(_ fixture: String = crossing) async throws -> TypeTwoFilm {
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        return TypeTwoFilm(
            line: try XCTUnwrap(LinearTimeline(
                trip: trip, config: config, establishing: nil, locale: locale
            )),
            trip: trip, config: config
        )
    }
}
