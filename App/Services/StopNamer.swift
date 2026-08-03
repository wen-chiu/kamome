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
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
                guard let self else { return }
                self.isWorking = false
                let finishedAt = Date.now.timeIntervalSince1970
                if let name = Self.displayName(from: placemarks?.first) {
                    self.policy.recordLookup(lat: stop.lat, lon: stop.lon, name: name, at: finishedAt)
                    try? self.repository.setStopName(stopId: stop.id, name: name)
                    self.onNamed?()
                } else {
                    // **Charge the throttle anyway.** Advancing the clock only on
                    // success let one failure release the throttle for the whole
                    // remaining queue, so CLGeocoder — which rate-limits per app —
                    // got a burst instead of one request every `min_interval_s`,
                    // and every stop after the first failure failed with it.
                    self.policy.recordAttempt(at: finishedAt)
                    // And say so. This was `_`, so a rate-limited trip produced a
                    // film full of "Unnamed stop" with nothing anywhere naming a
                    // cause (Chiu 2026-08-03).
                    KamomeLog.geocode.error("""
                        stop naming failed for \(stop.id, privacy: .public) — \
                        \(error?.localizedDescription ?? "no placemark returned", privacy: .public). \
                        The stop stays unnamed; reopening trip detail re-queues it.
                        """)
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
