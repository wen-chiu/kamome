import Foundation
@testable import Kamome

/// Real stop names in a review render, without paying for them twice
/// (Chiu 2026-08-05).
///
/// **Why this exists.** The pilot harness composes a trip straight out of
/// `ImportService`, which cannot name a stop — `NewStop` has no name field — so
/// every card in every pilot said "Unnamed stop" while the shipped app named them
/// correctly. That gap caused the same false regression report twice, and it made
/// previews systematically misrepresent the finished film on the one attribute
/// that carries a place's identity.
///
/// **Why a cache.** Reverse geocoding is throttled at `geocode.min_interval_s`, so
/// naming Iceland's 65 stops costs ~130 s of wall clock. Paying that on every
/// re-render would make the harness unusable, and hammering Apple's service with
/// the same coordinates repeatedly is rude besides. The cache is keyed on rounded
/// coordinates, so the second render of a fixture is instant and — more
/// importantly — *deterministic*, which a live geocoder is not.
///
/// **Where the cache lives.** `Tests/Fixtures/trips/local/`, gitignored as a whole
/// directory (CLAUDE.md §0). Place names for a real trip are still a record of
/// where someone was, so they never enter the repository.
///
/// Opt-in via `KAMOME_GEOCODE_STOPS=1`. Off by default keeps CI hermetic and
/// offline, which the golden-frame gates require.
final class RecapReviewGeocoder: StopGeocoding {
    private let cacheURL: URL
    private let live: StopGeocoding
    private var cache: [String: String]
    private(set) var hits = 0
    private(set) var misses = 0

    /// `minIntervalS` is `geocode.min_interval_s`, for the shipping geocoder's gate.
    init(fixture: String, minIntervalS: Double, live: StopGeocoding? = nil) {
        cacheURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/trips/local/\(fixture)-names.json")
        self.live = live ?? CLGeocoderStopGeocoder(minIntervalS: minIntervalS)
        cache = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["KAMOME_GEOCODE_STOPS"] == "1"
    }

    /// ~11 m at four decimal places — finer than `GeocodePolicy`'s own cache grid,
    /// so this never merges two stops the app would have named separately.
    private func key(lat: Double, lon: Double) -> String {
        String(format: "%.4f,%.4f", lat, lon)
    }

    func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
        if let cached = cache[key(lat: lat, lon: lon)] {
            hits += 1
            DispatchQueue.main.async { completion(cached, nil) }
            return
        }
        misses += 1
        live.reverseGeocode(lat: lat, lon: lon) { [weak self] name, error in
            if let self, let name {
                self.cache[self.key(lat: lat, lon: lon)] = name
                self.persist()
            }
            completion(name, error)
        }
    }

    /// Town and time zone as well as the name (ADR file 2026-09-28: the frame
    /// shows the next town, so a desk render needs the towns). Cached beside the
    /// names, in `local/<fixture>-places.json`, gitignored like them; a stop the
    /// places cache has not seen is asked once more, even if its name is cached.
    func reverseGeocodeZoned(
        lat: Double, lon: Double, completion: @escaping (String?, String?, String?, Error?) -> Void
    ) {
        let key = key(lat: lat, lon: lon)
        if let place = places[key] {
            hits += 1
            DispatchQueue.main.async { completion(place.name, place.locality, place.zone, nil) }
            return
        }
        misses += 1
        live.reverseGeocodeZoned(lat: lat, lon: lon) { [weak self] name, locality, zone, error in
            if let self, let name {
                self.cache[key] = name
                self.places[key] = Place(
                    name: name, locality: locality, zone: zone,
                    part: self.places[key]?.part, country: self.places[key]?.country
                )
                self.persist()
            }
            completion(name, locality, zone, error)
        }
    }

    /// The whole answer, cached the same way. A place cached before the part
    /// of town or the country was kept (`part` or `country` absent) is asked
    /// once more.
    func reverseGeocodeStop(lat: Double, lon: Double, completion: @escaping (StopPlace, Error?) -> Void) {
        let key = key(lat: lat, lon: lon)
        if let place = places[key], let part = place.part, let country = place.country {
            hits += 1
            let answer = StopPlace(
                name: place.name, locality: place.locality, subLocality: part.isEmpty ? nil : part,
                timeZone: place.zone, countryCode: country.isEmpty ? nil : country
            )
            DispatchQueue.main.async { completion(answer, nil) }
            return
        }
        misses += 1
        live.reverseGeocodeStop(lat: lat, lon: lon) { [weak self] place, error in
            if let self, let name = place.name {
                self.cache[key] = name
                self.places[key] = Place(
                    name: name, locality: place.locality, zone: place.timeZone, part: place.subLocality ?? "",
                    country: place.countryCode ?? ""
                )
                self.persist()
            }
            completion(place, error)
        }
    }

    private struct Place: Codable {
        let name: String
        let locality: String?
        let zone: String?
        /// `subLocality`; "" = asked, none; absent = cached before it was kept.
        var part: String?
        /// `isoCountryCode`, the same three states as `part`.
        var country: String?
    }

    private var placesURL: URL {
        cacheURL.deletingLastPathComponent()
            .appendingPathComponent(cacheURL.lastPathComponent.replacingOccurrences(of: "-names", with: "-places"))
    }

    private lazy var places: [String: Place] = (try? Data(contentsOf: placesURL))
        .flatMap { try? JSONDecoder().decode([String: Place].self, from: $0) } ?? [:]

    private func persist() {
        if let data = try? JSONEncoder().encode(places) { try? data.write(to: placesURL) }
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL)
    }
}
