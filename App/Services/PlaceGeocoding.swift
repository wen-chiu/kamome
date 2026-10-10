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

extension PlaceName {
    /// **The country in the app's language now** (#266), from its code through
    /// iOS's own locale data — no lookup, nothing leaves the phone. The cached
    /// `country` is whatever language Apple answered in when the journey was
    /// first looked up, so after a language change every journey kept its old
    /// name. Falls back to the cached name when there is no code (at sea).
    ///
    /// Towns and regions have no such table; they stay as looked up.
    func localizedCountry(localization: String? = Bundle.main.preferredLocalizations.first) -> String? {
        guard let code = countryCode, let localization,
              let name = Locale(identifier: localization).localizedString(forRegionCode: code),
              !name.isEmpty, name.uppercased() != code.uppercased() // an unknown code comes back as itself
        else { return country }
        return name
    }
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
    private let priority: GeocodeGate.Priority
    private let minIntervalS: Double
    /// nil is the app's shared gate; a test passes its own.
    private let gate: GeocodeGate?

    /// Through `GeocodeGate`, behind any stop naming (#159): `priority` says
    /// what the answer is for, `minIntervalS` is `geocode.min_interval_s`.
    init(priority: GeocodeGate.Priority, minIntervalS: Double, gate: GeocodeGate? = nil) {
        self.priority = priority
        self.minIntervalS = minIntervalS
        self.gate = gate
    }

    func place(lat: Double, lon: Double) async -> PlaceName? {
        guard let place = await ask(lat: lat, lon: lon).place else { return nil }
        return PlaceName(
            country: place.country,
            countryCode: place.countryCode,
            region: place.administrativeArea,
            locality: place.locality
        )
    }

    @MainActor
    private func ask(lat: Double, lon: Double) async -> GeocodeGate.Answer {
        await (gate ?? .shared).place(lat: lat, lon: lon, priority: priority, minIntervalS: minIntervalS)
    }
}
