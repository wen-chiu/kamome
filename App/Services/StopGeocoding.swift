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
            ocean: placemark.ocean
        )
    }
}
