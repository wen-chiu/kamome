import Foundation

/// What a journey is called on its card: a destination and a flag.
struct JourneyName: Codable, Equatable {
    let title: String
    /// Regional-indicator flag for the country, or nil when no code came back.
    let flag: String?
}

/// **The naming rule** — pure, so it is tested without a geocoder.
///
/// "Whitehorse" for a journey that stayed in one place, "Japan" for one that
/// ranged across a country, and the region rather than the country for a
/// journey at home — a Taiwan road trip named "Taiwan" on every card says
/// nothing. The single-place threshold is `discovery.single_place_extent_m`.
enum JourneyNaming {
    /// - Parameters:
    ///   - place: the coarse place of the journey's busiest stop.
    ///   - home: the coarse place of home, if known.
    ///   - isSinglePlace: whether the journey's extent is under the threshold.
    static func name(place: PlaceName, home: PlaceName?, isSinglePlace: Bool) -> JourneyName? {
        let domestic = home?.countryCode != nil && home?.countryCode == place.countryCode
        let title: String?
        if isSinglePlace {
            title = place.locality ?? place.region ?? place.country
        } else if domestic {
            title = place.region ?? place.locality ?? place.country
        } else {
            title = place.country ?? place.region ?? place.locality
        }
        guard let title, !title.isEmpty else { return nil }
        return JourneyName(title: title, flag: flag(countryCode: place.countryCode))
    }

    /// The flag emoji for an ISO 3166-1 alpha-2 code, or nil for anything else.
    static func flag(countryCode: String?) -> String? {
        guard let code = countryCode?.uppercased(), code.count == 2,
              code.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        let base: UInt32 = 0x1F1E6 - 0x41 // regional indicator A − "A"
        var flag = ""
        for scalar in code.unicodeScalars {
            guard let indicator = Unicode.Scalar(base + scalar.value) else { return nil }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }
}

/// Places already looked up, keyed by journey, kept on device so a relaunch
/// does not ask Apple again. The **place** is cached, not the derived name:
/// the name depends on the journey's extent, and a journey that widens when
/// photographs are added must be renamed without another lookup (a "Rome"
/// that became Rome → Florence stayed "Rome" on the 2026-09-17 render). Place
/// *names* only — never a coordinate (§0).
struct JourneyNameCache {
    private let defaults: UserDefaults
    private static let key = "kamome.journeyPlaces"
    private static let homeKey = "kamome.homePlace"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func place(for journeyKey: String) -> PlaceName? {
        stored()[journeyKey]
    }

    func store(_ place: PlaceName, for journeyKey: String) {
        var places = stored()
        places[journeyKey] = place
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// The name for a journey, derived now from its cached place, home, and
    /// the extent the caller knows today.
    func name(for journeyKey: String, isSinglePlace: Bool) -> JourneyName? {
        guard let place = place(for: journeyKey) else { return nil }
        return JourneyNaming.name(place: place, home: home(), isSinglePlace: isSinglePlace)
    }

    /// Home's coarse place, looked up once.
    func home() -> PlaceName? {
        guard let data = defaults.data(forKey: Self.homeKey) else { return nil }
        return try? JSONDecoder().decode(PlaceName.self, from: data)
    }

    func storeHome(_ place: PlaceName) {
        if let data = try? JSONEncoder().encode(place) {
            defaults.set(data, forKey: Self.homeKey)
        }
    }

    private func stored() -> [String: PlaceName] {
        guard let data = defaults.data(forKey: Self.key),
              let places = try? JSONDecoder().decode([String: PlaceName].self, from: data)
        else { return [:] }
        return places
    }
}

/// Discovered journeys the user swiped away. Keys only.
struct DismissedJourneys {
    private let defaults: UserDefaults
    private static let key = "kamome.dismissedJourneys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var keys: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func dismiss(_ journeyKey: String) {
        defaults.set(Array(keys.union([journeyKey])).sorted(), forKey: Self.key)
    }
}
