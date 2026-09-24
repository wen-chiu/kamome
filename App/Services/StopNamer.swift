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
    /// `townOnly` entries already have a name — the user's, or an earlier
    /// lookup's — and are asked only for their town, which never touches the name
    /// and never counts towards `progress` (ADR 2026-09-24 (e)).
    private var queue: [(stop: StopRecord, townOnly: Bool)] = []
    /// Towns by the name the lookup returned, so a stop answered from
    /// `GeocodePolicy`'s name cache still gets its town.
    private var localityByName: [String: String] = [:]
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
        let pending = stops.filter(Self.needsName)
        // Before any town-only entry: names gate the export, towns do not.
        let firstTownOnly = queue.firstIndex(where: { $0.townOnly }) ?? queue.endIndex
        queue.insert(contentsOf: pending.map { (stop: $0, townOnly: false) }, at: firstTownOnly)
        progress.total += pending.count
        publish()
        drain()
    }

    /// Asks for the town of every stop that has a name but was named before
    /// schema v9 kept towns. Fire-and-forget, behind any naming, on the same
    /// throttle; the name is never rewritten — it may be the user's own.
    func fillMissingLocalities(_ stops: [StopRecord]) {
        queue.append(contentsOf: stops.filter(Self.needsLocality).map { (stop: $0, townOnly: true) })
        drain()
    }

    /// Named, but never asked for its town. A stop that still needs a name gets
    /// its town from that lookup instead.
    static func needsLocality(_ stop: StopRecord) -> Bool {
        stop.locality == nil && !needsName(stop)
    }

    /// Unnamed — or named with a bare coordinate, which is what the open-sea
    /// placemark's `name` was stored as before 2026-09-23. Those are re-queued
    /// so trips imported earlier heal on their next open.
    static func needsName(_ stop: StopRecord) -> Bool {
        stop.name.map(StopDisplayName.isCoordinate) ?? true
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
        let (stop, townOnly) = queue.removeFirst()
        let now = Date.now.timeIntervalSince1970

        switch policy.decision(lat: stop.lat, lon: stop.lon, now: now) {
        case .cached(let name) where !townOnly:
            Stored.write("setStopName") { try repository.setStopName(stopId: stop.id, name: name) }
            if let town = localityByName[name] { storeLocality(town, of: stop) }
            finish(named: true)
            drain()
        case .cached(let name):
            if let town = localityByName[name] { storeLocality(town, of: stop) }
            drain()
        case .throttled(let retryAfterS):
            queue.insert((stop: stop, townOnly: townOnly), at: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + retryAfterS) { [weak self] in
                self?.drain()
            }
        case .lookup:
            isWorking = true
            geocoder.reverseGeocodePlace(lat: stop.lat, lon: stop.lon) { [weak self] name, locality, error in
                guard let self else { return }
                self.isWorking = false
                self.record(stop, townOnly: townOnly, name: name, locality: locality, error: error)
                self.drain()
            }
        }
    }

    /// One lookup's answer, written back. Pulled out of `drain` for length.
    private func record(_ stop: StopRecord, townOnly: Bool, name: String?, locality: String?, error: Error?) {
        let finishedAt = Date.now.timeIntervalSince1970
        guard let name else {
            // **Charge the throttle anyway.** Advancing the clock only on
            // success let one failure release the throttle for the whole
            // remaining queue, so CLGeocoder — which rate-limits per app —
            // got a burst instead of one request every `min_interval_s`,
            // and every stop after the first failure failed with it.
            policy.recordAttempt(at: finishedAt)
            // A town-only miss stays NULL, so the next open asks again.
            guard !townOnly else { return }
            // And say so. This was `_`, so a rate-limited trip produced a
            // film full of "Unnamed stop" with nothing anywhere naming a
            // cause (Chiu 2026-08-03).
            KamomeLog.geocode.error("""
                stop naming failed for \(stop.id, privacy: .public) — \
                \(error?.localizedDescription ?? "no placemark returned", privacy: .public). \
                The stop stays unnamed; reopening trip detail re-queues it.
                """)
            finish(named: false)
            return
        }
        policy.recordLookup(lat: stop.lat, lon: stop.lon, name: name, at: finishedAt)
        // "" = asked, no town here: recorded so it is not asked again.
        let town = locality ?? ""
        localityByName[name] = town
        storeLocality(town, of: stop)
        guard !townOnly else { return }
        Stored.write("setStopName") { try repository.setStopName(stopId: stop.id, name: name) }
        finish(named: true)
    }

    private func storeLocality(_ town: String, of stop: StopRecord) {
        Stored.write("setStopLocality") { try repository.setStopLocality(stopId: stop.id, locality: town) }
    }
}
