import Foundation

/// Picks the stop-card name from reverse-geocode fields (§4.2).
///
/// The 2026-07-18 drive named an urban Taoyuan stop "臺灣島" (Taiwan Island):
/// Apple's geocoder answers ordinary Taiwan coordinates with island-scale
/// features through `areasOfInterest` and feature-only placemarks' `name`.
/// So: `name` is trusted only when the placemark carries address context
/// (a street or neighborhood), proving it describes somewhere, not something
/// the size of the island; `areasOfInterest` is not consulted at all. True
/// POI naming via MKLocalSearch is an icebox item.
public enum StopDisplayName {
    public static func choose(
        name: String? = nil,
        thoroughfare: String? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        inlandWater: String? = nil,
        ocean: String? = nil
    ) -> String? {
        let coarse = Set([administrativeArea, country, inlandWater, ocean].compactMap { $0 })
        let hasAddressContext = thoroughfare != nil || subLocality != nil
        if let name, hasAddressContext, !coarse.contains(name) {
            return name
        }
        // Last-resort `name`: a placemark with no address fields and no
        // locality is genuinely remote — whatever feature name it has beats
        // an unnamed stop.
        return thoroughfare ?? subLocality ?? locality ?? name
    }
}
