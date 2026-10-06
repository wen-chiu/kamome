import Foundation
import KamomeConfig
import KamomePersistence

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
///
/// **"At home" is decided by the device's region setting, never by looking home
/// up** (2026-09-18). The rule only ever needed home's *country*, and the first
/// version got it by sending the detector's estimate of where the user lives to
/// Apple's geocoder — the single most sensitive coordinate in the library, sent
/// without asking, to answer a question the device already knows. The region
/// setting is a proxy, not a measurement: someone whose region is not where
/// they live gets a domestic trip named by country instead of region. That is a
/// naming cost; the lookup it replaced was a privacy cost.
enum JourneyNaming {
    /// - Parameters:
    ///   - place: the coarse place of the journey's busiest stop.
    ///   - homeCountryCode: ISO 3166-1 alpha-2 of home — the device's region.
    ///   - isSinglePlace: whether the journey's extent is under the threshold.
    static func name(place: PlaceName, homeCountryCode: String?, isSinglePlace: Bool) -> JourneyName? {
        let domestic = homeCountryCode != nil
            && homeCountryCode?.uppercased() == place.countryCode?.uppercased()
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
    private static let singlePlaceKey = "kamome.journeySinglePlaces"

    /// Where places are kept. In a `-demo-discover` run it is the demo's own
    /// throwaway suite, so Home, Trip Detail and the film read the names the
    /// demo list wrote, and a demo run still never names a real trip. A trip
    /// made from Discovery is stored unnamed (#165), so a screen reading
    /// another store would show its date where the list shows its place.
    static var store: UserDefaults {
        #if DEBUG
        if let demo = DemoJourneyLibrary.ifRequested() { return demo.defaults }
        #endif
        return .standard
    }

    init(defaults: UserDefaults = JourneyNameCache.store) {
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

    /// The name for a journey, derived now from its cached place, home's
    /// country and the extent the caller knows today.
    func name(for journeyKey: String, homeCountryCode: String?, isSinglePlace: Bool) -> JourneyName? {
        guard let place = place(for: journeyKey) else { return nil }
        return JourneyNaming.name(place: place, homeCountryCode: homeCountryCode, isSinglePlace: isSinglePlace)
    }

    /// Whether the journey stayed in one place, as last measured by whoever
    /// had its stops in hand: trip creation, a Discovery card being opened, or
    /// Trip Detail reading the trip (which re-measures after a merge or a
    /// deleted stop). Kept because Home's row holds only the trip record, and
    /// the rule that titles a one-town trip by its town (Chiu 2026-10-01) must
    /// not cost a read per row. A key that was never measured reads as wide.
    func isSinglePlace(_ journeyKey: String) -> Bool {
        singlePlaces().contains(journeyKey)
    }

    func setSinglePlace(_ isSinglePlace: Bool, for journeyKey: String) {
        var keys = singlePlaces()
        guard keys.contains(journeyKey) != isSinglePlace else { return }
        if isSinglePlace { keys.insert(journeyKey) } else { keys.remove(journeyKey) }
        defaults.set(keys.sorted(), forKey: Self.singlePlaceKey)
    }

    private func singlePlaces() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.singlePlaceKey) ?? [])
    }

    /// Home's country, from the device's region setting. Local; nothing is
    /// looked up to answer it.
    static var deviceHomeCountryCode: String? {
        Locale.current.region?.identifier
    }

    private func stored() -> [String: PlaceName] {
        guard let data = defaults.data(forKey: Self.key),
              let places = try? JSONDecoder().decode([String: PlaceName].self, from: data)
        else { return [:] }
        return places
    }
}

/// Names a trip outside the Journey Discovery beta, so the home card can show
/// a place and a flag without the beta ever having opened it.
///
/// **§0 scope.** One coordinate goes to Apple's geocoder — the trip's *first
/// stop*, already a stop point under the decided exception (ADR 2026-09-16
/// §4/PR #72), the same category `StopNamer` already sends. This is not the
/// centroid-of-all-photos fallback Chiu had removed from Discovery (ADR
/// 2026-09-18 (c)) — that geocoded a point that was nobody's stop. A single
/// named stop is.
///
/// **Timing, by Chiu's own call (2026-09-22):** proactive, at trip creation —
/// not deferred to whenever Trip Detail happens to be opened, because a title
/// that sometimes has a place and sometimes does not, depending on which
/// screen the user visited first, reads as broken rather than considered.
///
/// **First stop, not busiest** (unlike Discovery's journey naming): a smaller
/// judgement, accepted for now. A trip that crosses into a second country
/// keeps one representative flag here; showing every country is deferred to
/// Trip Detail, where the full stop list is already being read.
enum TripJourneyNaming {
    static func nameIfNeeded(
        tripId: String,
        repository: TripRepository,
        geocode: TrackingConfig.Geocode,
        singlePlaceExtentM: Double,
        geocoder: PlaceGeocoding? = nil,
        cache: JourneyNameCache = JourneyNameCache()
    ) {
        // Through the shared gate, behind stop names and ahead of Discovery's
        // cards (#159). It asks about the first stop, which `StopNamer` is
        // often asking about at the same moment: the gate sends one request.
        let geocoder = geocoder ?? CLPlaceGeocoder(priority: .tripFlag, minIntervalS: geocode.minIntervalS)
        guard let detail = Stored.read("detail", { try repository.detail(tripId: tripId) }),
              let first = detail.stops.first
        else { return }
        // Measured while the stops are in hand: a one-town trip is titled by
        // its town, and Home's row cannot measure it (`TripTitle.place`).
        cache.setSinglePlace(TripTitle.isSinglePlace(detail.stops, under: singlePlaceExtentM), for: tripId)
        guard cache.place(for: tripId) == nil else { return }
        Task {
            if let place = await geocoder.place(lat: first.lat, lon: first.lon) {
                cache.store(place, for: tripId)
            }
        }
    }
}

/// Discovered journeys the user hid. Keys only. Shown again from the hidden
/// row at the foot of the Discovery list (#167).
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

    func restore(_ journeyKey: String) {
        defaults.set(Array(keys.subtracting([journeyKey])).sorted(), forKey: Self.key)
    }
}
