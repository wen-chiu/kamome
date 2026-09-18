import CoreLocation
import Foundation

/// A coarse answer to "where is this?" — the fields a journey's name is built
/// from. Codable so the answer can be cached on device and never asked twice.
struct PlaceName: Codable, Equatable {
    let country: String?
    /// ISO 3166-1 alpha-2, the source of the card's flag.
    let countryCode: String?
    /// State, prefecture, region — `administrativeArea`.
    let region: String?
    /// Town or city — `locality`.
    let locality: String?
}

/// The one capability journey naming needs from the outside world, on the same
/// seam `StopGeocoding` cut for stop naming and for the same reason: the Apple
/// call is the only thing tests cannot drive, so it is the only thing behind
/// the protocol.
protocol PlaceGeocoding: AnyObject {
    /// Resolves one coordinate to a coarse place, or nil when nothing came back.
    func place(lat: Double, lon: Double) async -> PlaceName?
}

/// The shipping implementation. Honours the device locale like the stop
/// geocoder, so country and town names arrive in the user's language.
///
/// **§0 note.** This sends one coordinate per journey to Apple's geocoder, the
/// same service stop naming already uses and the privacy notice already names
/// ("place names come from Apple"). The difference is *when*: stop naming runs
/// after the user imports a trip, this runs when a journey is discovered. That
/// timing is a product decision recorded in the ADR of 2026-09-17, not an
/// implementation detail.
final class CLPlaceGeocoder: PlaceGeocoding {
    private let geocoder = CLGeocoder()

    func place(lat: Double, lon: Double) async -> PlaceName? {
        let location = CLLocation(latitude: lat, longitude: lon)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return PlaceName(
            country: placemark.country,
            countryCode: placemark.isoCountryCode,
            region: placemark.administrativeArea,
            locality: placemark.locality
        )
    }
}
