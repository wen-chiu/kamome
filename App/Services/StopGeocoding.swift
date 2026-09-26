import CoreLocation
import Foundation
import KamomeTripComposer

/// The one capability `StopNamer` needs from the outside world: a coordinate in,
/// a display name out.
///
/// **Why this is a protocol** (2026-08-04). `StopNamer` owned a concrete
/// `CLGeocoder`, and the only call site is `TripDetailModel.load()`. That made
/// the naming path unreachable from any test: the throttle fix of 2026-08-03
/// shipped "green" against `GeocodePolicy` alone — a pure struct that knows
/// nothing about queues, retries, or the database — and the symptom it was meant
/// to cure went on appearing in real films because nothing had ever exercised the
/// code between the policy and the DB write.
///
/// The seam is deliberately narrow. Everything interesting (the queue, the
/// throttle, the retry, the DB write) stays in `StopNamer` where it can now be
/// driven by a stub; only the Apple call itself is on the other side.
protocol StopGeocoding: AnyObject {
    /// Resolves one coordinate. `name` is nil when the lookup produced no usable
    /// placemark; `error` carries the reason when there was one. Both nil-name
    /// outcomes — error and empty — must still charge the throttle, which is the
    /// caller's job.
    ///
    /// The completion is called on the main queue.
    func reverseGeocode(
        lat: Double, lon: Double, completion: @escaping (_ name: String?, _ error: Error?) -> Void
    )

    /// The same lookup, also answering the **town** the stop is in
    /// (`CLPlacemark.locality`) for the film's HUD pill (ADR 2026-09-24 (e)).
    /// One request either way. Defaulted below to `reverseGeocode` with no town,
    /// so a stub that only names stops still conforms.
    func reverseGeocodePlace(
        lat: Double, lon: Double,
        completion: @escaping (_ name: String?, _ locality: String?, _ error: Error?) -> Void
    )

    /// The same one lookup, also returning the placemark's time zone
    /// identifier — what a stop's local day is counted in (`TripClock`, arch
    /// review 2026-09-26). Nothing more leaves the phone than the lookup that
    /// names the stop already sends.
    func reverseGeocodeZoned(
        lat: Double, lon: Double,
        completion: @escaping (_ name: String?, _ locality: String?, _ timeZone: String?, _ error: Error?) -> Void
    )
}

extension StopGeocoding {
    func reverseGeocodePlace(
        lat: Double, lon: Double, completion: @escaping (String?, String?, Error?) -> Void
    ) {
        reverseGeocode(lat: lat, lon: lon) { name, error in completion(name, nil, error) }
    }

    func reverseGeocodeZoned(
        lat: Double, lon: Double, completion: @escaping (String?, String?, String?, Error?) -> Void
    ) {
        reverseGeocodePlace(lat: lat, lon: lon) { name, locality, error in completion(name, locality, nil, error) }
    }
}

/// The shipping implementation: CLGeocoder, honoring device locale so Chinese
/// place names come back natively (§1.7).
final class CLGeocoderStopGeocoder: StopGeocoding {
    private let geocoder = CLGeocoder()

    func reverseGeocode(
        lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void
    ) {
        geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { placemarks, error in
            completion(Self.displayName(from: placemarks?.first), error)
        }
    }

    func reverseGeocodePlace(
        lat: Double, lon: Double, completion: @escaping (String?, String?, Error?) -> Void
    ) {
        reverseGeocodeZoned(lat: lat, lon: lon) { name, locality, _, error in completion(name, locality, error) }
    }

    func reverseGeocodeZoned(
        lat: Double, lon: Double, completion: @escaping (String?, String?, String?, Error?) -> Void
    ) {
        geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { placemarks, error in
            let placemark = placemarks?.first
            completion(Self.displayName(from: placemark), placemark?.locality, placemark?.timeZone?.identifier, error)
        }
    }

    private static func displayName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        return StopDisplayName.choose(
            name: placemark.name,
            thoroughfare: placemark.thoroughfare,
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            inlandWater: placemark.inlandWater,
            ocean: placemark.ocean,
            areasOfInterest: placemark.areasOfInterest
        )
    }
}
