import Foundation

/// Picks the stop-card name from reverse-geocode fields (§4.2).
///
/// **Priority: named landmark → town → nothing** (Chiu 2026-08-06). What a viewer
/// wants on a card is the place they went — "Glacier Lagoon", not the town 60 km
/// away and not a street address.
///
/// The old rule trusted `name` only when the placemark carried address context (a
/// street or a neighbourhood), because the 2026-07-18 drive named an urban Taoyuan
/// stop "臺灣島" — Apple answers ordinary coordinates with island-scale features.
/// That guard threw away exactly the names worth having: a remote waterfall has no
/// street, so `name` was skipped and the film showed the nearest town.
///
/// Measured against six real Iceland stops (2026-08-06) the guard is replaced by
/// three specific rejections instead of one blunt precondition:
///
/// | placemark `name` | verdict | shown |
/// |---|---|---|
/// | `Glacier Lagoon` | landmark | **Glacier Lagoon** (was: Höfn í Hornafirði) |
/// | `871`, `781`, `806`, `785` | road number | falls through to the town |
/// | `Norðurgata 10` | street address | falls through to Seyðisfjörður |
///
/// `areasOfInterest` is now consulted, but only *below* `name` and only after the
/// same coarse filter — it answers "Vatnajökull National Park" for one stop and a
/// bare "Iceland" for most, which is the island-scale problem in its original form.
public enum StopDisplayName {
    public static func choose(
        name: String? = nil,
        thoroughfare: String? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        inlandWater: String? = nil,
        ocean: String? = nil,
        areasOfInterest: [String]? = nil
    ) -> String? {
        let coarse = Set([administrativeArea, country, ocean].compactMap { $0 })
        let regions = [administrativeArea, country].compactMap { $0 }

        if let name, isLandmark(name, thoroughfare: thoroughfare, coarse: coarse, regions: regions) {
            return name
        }
        // `areasOfInterest` is ordered most-specific-first, and Apple appends the
        // containing region: Aoraki/Mount Cook National Park **then** South Island.
        // A list of *one* entry is therefore just the region — "South Island",
        // "Iceland" — which is the 臺灣島 failure wearing different clothes. Only a
        // list that has something after the first entry has a real landmark in it.
        if let interests = areasOfInterest, interests.count > 1,
           let interest = interests.first(where: {
               isLandmark($0, thoroughfare: thoroughfare, coarse: coarse, regions: regions)
           }) {
            return interest
        }
        // The town, then — failing that — the address. An address is a poor card
        // title, but "Unnamed stop" reads as a bug to anyone watching, while a
        // street at least looks like a deliberate answer (Chiu 2026-08-06).
        if let town = locality ?? subLocality { return town }
        return name ?? thoroughfare
    }

    /// Is this a place someone went, rather than a region, a road, or an address?
    ///
    /// - *Coarse* rejects the island-scale answers (`administrativeArea`,
    ///   `country`, `ocean`). `inlandWater` is deliberately **not** coarse: for a
    ///   glacier lagoon it *is* the landmark.
    /// - *Numeric* rejects route numbers. Iceland returns "871" and "781" as
    ///   `name`, which is strictly worse than the nearest town.
    /// - *Address* rejects a `name` that **contains** its own `thoroughfare`.
    ///   Containment rather than a prefix, because house numbers go on opposite
    ///   ends in different countries: Iceland writes "Norðurgata 10", New Zealand
    ///   writes "15 Tyne St". A prefix test caught the first and missed the second,
    ///   which is why Iceland's names looked right while NZ showed addresses
    ///   (2026-08-06). "Ashley Gorge Recreation Reserve" on "Ashley Gorge Rd"
    ///   survives — it contains the road's *stem*, not the road.
    /// - *Region-scale* rejects "臺灣島". This is the 2026-07-18 defect, and an
    ///   exact match against the coarse fields does not catch it: the geocoder
    ///   answers `name` = 臺灣島 while `country` = 台灣, which are different
    ///   strings. What gives it away is that the name **embeds** its own country
    ///   or region — something that size is not a place you went. It has to be a
    ///   containment test rather than equality, and it has to normalise 臺/台,
    ///   which are variant forms of one character that Apple mixes between fields.
    ///
    ///   Deliberately narrow: 龜山島 survives (a real islet, and no country field
    ///   accompanies it) and 桃園觀光夜市 survives (it contains 桃園, but not the
    ///   full 桃園市). Widening this to bare prefixes would delete both.
    private static func isLandmark(
        _ candidate: String, thoroughfare: String?, coarse: Set<String>, regions: [String]
    ) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coarse.contains(trimmed) else { return false }
        guard trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil else { return false }
        if let thoroughfare, !thoroughfare.isEmpty, trimmed.contains(thoroughfare) { return false }
        let normalized = normalize(trimmed)
        if regions.contains(where: { !$0.isEmpty && normalized.contains(normalize($0)) }) { return false }
        return true
    }

    /// Folds the character variants Apple mixes between placemark fields. Only
    /// 臺/台 so far — added because it is the one that actually broke a film, not
    /// because a general transliteration table would be nice to have.
    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "臺", with: "台")
    }
}
