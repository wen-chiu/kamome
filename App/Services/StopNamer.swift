import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTripComposer

/// §4.2 stop naming: throttled + cached via `GeocodePolicy`, over whatever
/// `StopGeocoding` supplies (CLGeocoder in the app, a stub in tests).
///
/// **It reports progress** (2026-08-04). Naming is asynchronous and throttled at
/// `geocode.min_interval_s`, so an 18-stop imported trip takes ~36 s of wall
/// clock after Trip Detail opens. Nothing used to expose that, so the film button
/// was live the whole time and exporting early baked "Unnamed stop" into the
/// video — the exact symptom the throttle fix was meant to remove, reachable
/// without any throttle bug at all. The UI can now wait for `progress.isFinished`.
final class StopNamer {
    /// How far naming has got. `completed` counts stops that have *left* the
    /// queue for good — named, cached, or given up on — because a stop that
    /// failed is as finished as one that succeeded, and a UI that waits for
    /// successes alone would wait forever on a trip with no coverage.
    struct Progress: Equatable {
        var total: Int = 0
        var completed: Int = 0
        var named: Int = 0
        var isFinished: Bool { completed >= total }
    }

    private let geocoder: StopGeocoding
    private var policy: GeocodePolicy
    private let repository: TripRepository
    private var queue: [StopRecord] = []
    private var isWorking = false
    private var onChange: ((Progress) -> Void)?
    private(set) var progress = Progress()

    /// Takes `TrackingConfig.Geocode`, not the whole config — it is the only part
    /// this ever read, and narrowing it is what lets a test run the real queue at
    /// a 50 ms throttle instead of the shipped 2 s.
    init(
        config: TrackingConfig.Geocode,
        repository: TripRepository,
        geocoder: StopGeocoding = CLGeocoderStopGeocoder()
    ) {
        policy = GeocodePolicy(config: config)
        self.repository = repository
        self.geocoder = geocoder
    }

    /// Names every unnamed stop, respecting the throttle. Fire-and-forget;
    /// results land in the DB. `onChange` fires (main thread) whenever progress
    /// moves, so the caller can reload the trip *and* show how far naming has
    /// got — a photo-dense imported trip is geocoded over ~30 s (§4.2), well past
    /// any one-shot refresh.
    func nameUnnamedStops(_ stops: [StopRecord], onChange: ((Progress) -> Void)? = nil) {
        if let onChange { self.onChange = onChange }
        let pending = stops.filter { $0.name == nil }
        queue.append(contentsOf: pending)
        progress.total += pending.count
        publish()
        drain()
    }

    private func publish() {
        onChange?(progress)
    }

    /// One stop has left the queue for good.
    private func finish(named: Bool) {
        progress.completed += 1
        if named { progress.named += 1 }
        publish()
    }

    private func drain() {
        guard !isWorking, !queue.isEmpty else { return }
        let stop = queue.removeFirst()
        let now = Date.now.timeIntervalSince1970

        switch policy.decision(lat: stop.lat, lon: stop.lon, now: now) {
        case .cached(let name):
            try? repository.setStopName(stopId: stop.id, name: name)
            finish(named: true)
            drain()
        case .throttled(let retryAfterS):
            queue.insert(stop, at: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + retryAfterS) { [weak self] in
                self?.drain()
            }
        case .lookup:
            isWorking = true
            geocoder.reverseGeocode(lat: stop.lat, lon: stop.lon) { [weak self] name, error in
                guard let self else { return }
                self.isWorking = false
                let finishedAt = Date.now.timeIntervalSince1970
                if let name {
                    self.policy.recordLookup(lat: stop.lat, lon: stop.lon, name: name, at: finishedAt)
                    try? self.repository.setStopName(stopId: stop.id, name: name)
                    self.finish(named: true)
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
                    self.finish(named: false)
                }
                self.drain()
            }
        }
    }
}
