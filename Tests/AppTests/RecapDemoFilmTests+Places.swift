import Foundation
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import XCTest

/// Where a desk film's stops are: their names through Apple when
/// `KAMOME_GEOCODE_STOPS=1`, else only their countries, offline. Split out of
/// `RecapDemoFilmTests` at its file-length limit.
extension RecapDemoFilmTests {
    /// Names the stops through Apple when asked to, else gives them only their
    /// countries, offline (`stampCountries`).
    static func placeStops(
        tripId: String, fixture: String, repository: TripRepository, config: TrackingConfig
    ) async throws {
        guard RecapReviewGeocoder.isEnabled else {
            return try stampCountries(tripId: tripId, repository: repository)
        }
        try await nameStops(tripId: tripId, fixture: fixture, repository: repository, config: config)
    }

    /// **An offline stand-in for the country Apple names a stop in** (ADR file
    /// 2026-10-03), so a hermetic render still has its boarding pass: the
    /// shipped app stores `CLPlacemark.isoCountryCode`, which CI cannot ask for.
    /// `CountryExtent`'s boxes are coarse but cover every committed fixture; a
    /// stop outside them is stored "" — asked, none — as a stop at sea is.
    static func stampCountries(tripId: String, repository: TripRepository) throws {
        for stop in try XCTUnwrap(try repository.detail(tripId: tripId)).stops {
            let code = CountryExtent.containing(lat: stop.lat, lon: stop.lon)?.isoCode ?? ""
            try repository.setStopCountryCode(stopId: stop.id, countryCode: code)
        }
    }

    /// Runs the **shipped** `StopNamer` over the trip's stops and waits for it to
    /// finish, so what the pilot renders is what the app would have written.
    static func nameStops(
        tripId: String, fixture: String, repository: TripRepository, config: TrackingConfig
    ) async throws {
        let stops = try XCTUnwrap(try repository.detail(tripId: tripId)).stops
        let geocoder = RecapReviewGeocoder(fixture: fixture, minIntervalS: config.geocode.minIntervalS)
        let namer = StopNamer(config: config.geocode, repository: repository, geocoder: geocoder)
        let started = Date.now
        await withCheckedContinuation { continuation in
            var resumed = false
            namer.nameUnnamedStops(stops) { progress in
                guard progress.isFinished, !resumed else { return }
                resumed = true
                continuation.resume()
            }
        }
        print(String(
            format: "KAMOME_GEOCODE_STOPS %d/%d named · %d cached, %d looked up · %.0fs",
            namer.progress.named, namer.progress.total, geocoder.hits, geocoder.misses,
            Date.now.timeIntervalSince(started)
        ))
    }
}
