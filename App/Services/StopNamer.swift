import CoreLocation
import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTripComposer

/// CLGeocoder adapter for §4.2 stop naming: throttled + cached via
/// GeocodePolicy, honors device locale (Chinese place names natively, §1.7).
final class StopNamer {
    private let geocoder = CLGeocoder()
    private var policy: GeocodePolicy
    private let repository: TripRepository
    private var queue: [StopRecord] = []
    private var isWorking = false
    private var onNamed: (() -> Void)?

    init(config: TrackingConfig, repository: TripRepository) {
        policy = GeocodePolicy(config: config.geocode)
        self.repository = repository
    }

    /// Names every unnamed stop, respecting the throttle. Fire-and-forget;
    /// results land in the DB. `onNamed` fires (main thread) each time a name
    /// is written so the caller can reload — a photo-dense imported trip can
    /// have many stops geocoded over ~30 s past a one-shot refresh (§4.2).
    func nameUnnamedStops(_ stops: [StopRecord], onNamed: (() -> Void)? = nil) {
        if let onNamed { self.onNamed = onNamed }
        queue.append(contentsOf: stops.filter { $0.name == nil })
        drain()
    }

    private func drain() {
        guard !isWorking, !queue.isEmpty else { return }
        let stop = queue.removeFirst()
        let now = Date.now.timeIntervalSince1970

        switch policy.decision(lat: stop.lat, lon: stop.lon, now: now) {
        case .cached(let name):
            try? repository.setStopName(stopId: stop.id, name: name)
            onNamed?()
            drain()
        case .throttled(let retryAfterS):
            queue.insert(stop, at: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + retryAfterS) { [weak self] in
                self?.drain()
            }
        case .lookup:
            isWorking = true
            let location = CLLocation(latitude: stop.lat, longitude: stop.lon)
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                guard let self else { return }
                self.isWorking = false
                if let name = Self.displayName(from: placemarks?.first) {
                    self.policy.recordLookup(lat: stop.lat, lon: stop.lon, name: name, at: Date.now.timeIntervalSince1970)
                    try? self.repository.setStopName(stopId: stop.id, name: name)
                    self.onNamed?()
                }
                self.drain()
            }
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
