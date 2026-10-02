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
    /// Zones by the same name, for the same reason (`TripClock`).
    private var zoneByName: [String: String] = [:]
    private var isWorking = false
    /// The stop whose lookup is out, so it is not queued a second time.
    private var inFlightId: String?
    private var inFlightTownOnly = false
    /// Stops whose lookup has failed once and been put back for one more try
    /// (Chiu 2026-10-01, #160). A second failure is final.
    private var retriedIds: Set<String> = []
    /// Stops this namer has named. A caller's copy of the trip can be a read
    /// behind, and would hand a stop back as unnamed just after its name landed.
    private var namedIds: Set<String> = []
    private var onChange: ((Progress) -> Void)?
    private var onPlaceFilled: (() -> Void)?
    /// Called each time the queue runs empty with nothing in flight — names
    /// and towns both. `StopNamingCoordinator` lets go of the namer then.
    var onDrained: (() -> Void)?
    private(set) var progress = Progress()

    /// Takes `TrackingConfig.Geocode`, not the whole config — it is the only part
    /// this ever read, and narrowing it is what lets a test run the real queue at
    /// a 50 ms throttle instead of the shipped 2 s.
    init(
        config: TrackingConfig.Geocode,
        repository: TripRepository,
        geocoder: StopGeocoding? = nil
    ) {
        policy = GeocodePolicy(config: config)
        self.repository = repository
        self.geocoder = geocoder ?? CLGeocoderStopGeocoder(minIntervalS: config.minIntervalS)
    }

    /// Names every unnamed stop, respecting the throttle. Fire-and-forget;
    /// results land in the DB. `onChange` fires (main thread) whenever progress
    /// moves, so the caller can reload the trip *and* show how far naming has
    /// got — a photo-dense imported trip is geocoded over ~30 s (§4.2), well past
    /// any one-shot refresh.
    func nameUnnamedStops(_ stops: [StopRecord], onChange: ((Progress) -> Void)? = nil) {
        if let onChange { self.onChange = onChange }
        // A stop already waiting or out is not asked twice: a screen reopened
        // mid-run hands over the same stops again (#159).
        let pending = stops.filter { Self.needsName($0) && !isPending($0) }
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
    ///
    /// `onFilled` fires (main thread) each time a town and zone land, so the
    /// screen that shows the stop's day and hour can read them (ADR 2026-10-01):
    /// without it a trip named before schema v14 kept the phone's clock until
    /// it was opened a second time.
    func fillMissingLocalities(_ stops: [StopRecord], onFilled: (() -> Void)? = nil) {
        if let onFilled { onPlaceFilled = onFilled }
        queue.append(contentsOf: stops.filter { Self.needsLocality($0) && !isPending($0) }
            .map { (stop: $0, townOnly: true) })
        drain()
    }

    /// Drops everything still waiting — the trip was deleted. A lookup already
    /// out lands on rows that are gone and writes nothing.
    func cancel() {
        queue.removeAll()
    }

    /// Nothing waiting and nothing out.
    var isIdle: Bool { !isWorking && queue.isEmpty }

    /// The stops still owed a name: waiting, out, or waiting for their retry.
    /// What the film button asks about (#160) — `progress` counts the whole trip.
    var pendingNameIds: Set<String> {
        var ids = Set(queue.filter { !$0.townOnly }.map(\.stop.id))
        if let inFlightId, !inFlightTownOnly { ids.insert(inFlightId) }
        return ids
    }

    /// Moves these stops to the front of the names still waiting, in the order
    /// they already had: the film's stops are named first, so the film button
    /// waits on the film's size and not the trip's (Chiu 2026-10-01, #160).
    func prioritise(_ stopIds: Set<String>) {
        let names = queue.filter { !$0.townOnly }
        let towns = queue.filter { $0.townOnly }
        queue = names.filter { stopIds.contains($0.stop.id) }
            + names.filter { !stopIds.contains($0.stop.id) } + towns
    }

    private func isPending(_ stop: StopRecord) -> Bool {
        inFlightId == stop.id || namedIds.contains(stop.id) || queue.contains { $0.stop.id == stop.id }
    }

    /// Named, but never asked for its town — or for its zone, which schema v14
    /// added later (arch review 2026-09-26). A stop that still needs a name gets
    /// both from that lookup instead.
    static func needsLocality(_ stop: StopRecord) -> Bool {
        (stop.locality == nil || stop.timeZone == nil) && !needsName(stop)
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
    private func finish(_ stop: StopRecord, named: Bool) {
        progress.completed += 1
        if named {
            progress.named += 1
            namedIds.insert(stop.id)
        }
        publish()
    }

    private func drain() {
        guard !isWorking else { return }
        guard !queue.isEmpty else {
            onDrained?()
            return
        }
        let (stop, townOnly) = queue.removeFirst()
        let now = Date.now.timeIntervalSince1970

        switch policy.decision(lat: stop.lat, lon: stop.lon, now: now) {
        case .cached(let name) where !townOnly:
            Stored.write("setStopName") { try repository.setStopName(stopId: stop.id, name: name) }
            storeCachedPlace(named: name, of: stop)
            finish(stop, named: true)
            drain()
        case .cached(let name):
            storeCachedPlace(named: name, of: stop)
            onPlaceFilled?()
            drain()
        case .throttled(let retryAfterS) where !geocoder.pacesItself:
            queue.insert((stop: stop, townOnly: townOnly), at: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + retryAfterS) { [weak self] in
                self?.drain()
            }
        case .lookup, .throttled:
            // `.throttled` lands here for a geocoder that paces itself: the
            // gate holds the lookup until its turn (`StopGeocoding.pacesItself`).
            isWorking = true
            inFlightId = stop.id
            inFlightTownOnly = townOnly
            geocoder.reverseGeocodeZoned(lat: stop.lat, lon: stop.lon) { [weak self] name, locality, zone, error in
                guard let self else { return }
                self.isWorking = false
                self.inFlightId = nil
                let place = Place(name: name, locality: locality, zone: zone)
                self.record(stop, townOnly: townOnly, place: place, error: error)
                self.drain()
            }
        }
    }

    /// One lookup's answer, written back. Pulled out of `drain` for length.
    /// What one lookup answered about a stop.
    private struct Place {
        let name: String?
        let locality: String?
        let zone: String?
    }

    private func record(_ stop: StopRecord, townOnly: Bool, place: Place, error: Error?) {
        let (name, locality) = (place.name, place.locality)
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
            let reason = error?.localizedDescription ?? "no placemark returned"
            // **One more try, after every other stop has been asked** (Chiu
            // 2026-10-01, #160): a lookup that failed once is often a rate
            // limit that has passed by the end of the queue. It goes behind the
            // names still waiting and is charged the throttle like any other.
            if retriedIds.insert(stop.id).inserted {
                KamomeLog.geocode.error("""
                    stop naming failed for \(stop.id, privacy: .public) — \(reason, privacy: .public). \
                    It is asked once more after the other stops.
                    """)
                let firstTownOnly = queue.firstIndex(where: { $0.townOnly }) ?? queue.endIndex
                queue.insert((stop: stop, townOnly: false), at: firstTownOnly)
                return
            }
            // And say so. This was `_`, so a rate-limited trip produced a
            // film full of "Unnamed stop" with nothing anywhere naming a
            // cause (Chiu 2026-08-03).
            KamomeLog.geocode.error("""
                stop naming failed twice for \(stop.id, privacy: .public) — \(reason, privacy: .public). \
                The stop stays unnamed; reopening trip detail re-queues it.
                """)
            finish(stop, named: false)
            return
        }
        policy.recordLookup(lat: stop.lat, lon: stop.lon, name: name, at: finishedAt)
        // "" = asked, no town (or zone) here: recorded so it is not asked again.
        let town = locality ?? ""
        let zone = place.zone ?? ""
        localityByName[name] = town
        zoneByName[name] = zone
        storeLocality(town, of: stop)
        storeTimeZone(zone, of: stop)
        guard !townOnly else {
            onPlaceFilled?()
            return
        }
        Stored.write("setStopName") { try repository.setStopName(stopId: stop.id, name: name) }
        finish(stop, named: true)
    }

    private func storeLocality(_ town: String, of stop: StopRecord) {
        Stored.write("setStopLocality") { try repository.setStopLocality(stopId: stop.id, locality: town) }
    }

    private func storeTimeZone(_ zone: String, of stop: StopRecord) {
        Stored.write("setStopTimeZone") { try repository.setStopTimeZone(stopId: stop.id, timeZone: zone) }
    }

    /// A stop answered from `GeocodePolicy`'s name cache gets the town and zone
    /// the lookup behind that name returned, when this session made it.
    private func storeCachedPlace(named name: String, of stop: StopRecord) {
        if let town = localityByName[name] { storeLocality(town, of: stop) }
        if let zone = zoneByName[name] { storeTimeZone(zone, of: stop) }
    }
}
