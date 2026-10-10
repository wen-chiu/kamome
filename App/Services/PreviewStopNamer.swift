import Foundation
import KamomeConfig
import KamomeImportKit
import KamomePersistence

/// **Names a found journey's places while its preview is open** (Footprints
/// ADR draft 2026-09-30, Data 3). One lookup per stop, ever:
///
/// - It asks only because the person opened the preview: the same stop-point
///   exception (ADR 2026-09-16, PR #72), at the same moment opening a journey
///   always asked. It goes through the shared gate at a stop's priority (#159).
/// - Leaving the preview cancels whatever is still waiting. A lookup already
///   out finishes and is kept.
/// - Answers are kept in memory for the session, keyed by the stop's position
///   (a found journey's place and the stop it becomes share their centroid).
///   They are never written to disk until 「新增旅程」 stores the trip.
/// - 「新增旅程」 writes them onto the new stops (`write(to:repository:)`), so
///   S3 names only what the preview never reached, and the film is not held
///   behind a second 2 s-per-stop wait.
@MainActor
final class PreviewStopNamer {
    struct Key: Hashable {
        let lat: Double
        let lon: Double
    }

    private let geocoder: StopGeocoding
    private var answers: [Key: StopPlace] = [:]
    /// Places whose lookup answered no name this session: not asked again by
    /// a preview, so the diary can say "unnamed" rather than "identifying"
    /// for good (#264). S3's own namer still asks after 「新增旅程」.
    private var missed: Set<Key> = []
    /// Places the run in flight has still to ask about.
    private var waiting: Set<Key> = []
    private var task: Task<Void, Never>?

    init(geocoder: StopGeocoding) {
        self.geocoder = geocoder
    }

    convenience init(config: TrackingConfig.Geocode) {
        self.init(geocoder: CLGeocoderStopGeocoder(minIntervalS: config.minIntervalS))
    }

    /// What the lookup answered for the stop here, if this session asked.
    func answer(lat: Double, lon: Double) -> StopPlace? {
        answers[Key(lat: lat, lon: lon)]
    }

    /// Whether this place's name is still coming: queued in the run in
    /// flight, not yet answered or missed.
    func isNaming(_ place: JourneyItinerary.Place) -> Bool {
        waiting.contains(Key(lat: place.lat, lon: place.lon))
    }

    /// The clock a found journey's days and times are counted by: each stop's
    /// own zone, from the answers this session holds, else the phone's. The
    /// stops the plan becomes get those zones at 「新增旅程」 (`write`), so a
    /// preview and S3 say the same hour and the same day.
    func clock(for plan: ImportedTripPlan) -> TripClock {
        TripClock(zones: plan.stops.compactMap { stop in
            guard let identifier = answer(lat: stop.lat, lon: stop.lon)?.timeZone,
                  let zone = TimeZone(identifier: identifier) else { return nil }
            return TripClock.StopZone(arrivedAt: stop.arrivedAt, departedAt: stop.departedAt, zone: zone)
        })
    }

    /// The itinerary with every answered place named.
    func named(_ itinerary: JourneyItinerary) -> JourneyItinerary {
        var named = itinerary
        for day in named.days.indices {
            for entry in named.days[day].entries.indices {
                let place = named.days[day].entries[entry].place
                if place.name == nil, let name = answer(lat: place.lat, lon: place.lon)?.name {
                    named.days[day].entries[entry].place.name = name
                }
            }
        }
        return named
    }

    /// Asks about each place with no answer yet, in order, one at a time —
    /// a place that answered nothing earlier this session is not asked again.
    /// `onChange` runs after each lookup, answered or not, so the screen can
    /// stop saying a name is coming. Replaces any run still going.
    func name(_ places: [JourneyItinerary.Place], onChange: @escaping () -> Void) {
        task?.cancel()
        let pending = places.map { Key(lat: $0.lat, lon: $0.lon) }
            .filter { answers[$0] == nil && !missed.contains($0) }
        waiting = Set(pending)
        guard !pending.isEmpty else { return }
        task = Task { [weak self] in
            for key in pending {
                guard !Task.isCancelled, let self else { return }
                guard self.answers[key] == nil else { continue }
                let place = await self.lookUp(key)
                self.waiting.remove(key)
                if place.name != nil {
                    self.answers[key] = place
                } else {
                    // Left for S3, whose namer tries again and says why.
                    self.missed.insert(key)
                    KamomeLog.geocode.notice("preview stop naming produced no name; S3 will ask")
                }
                onChange()
            }
        }
    }

    /// The preview has closed.
    func cancel() {
        task?.cancel()
        task = nil
        waiting = []
    }

    /// Writes every answer this session holds onto the stops at the same
    /// position: name, town, zone, part of town and country. A stop that
    /// already has a name keeps it.
    func write(to stops: [StopRecord], repository: TripRepository) {
        for stop in stops {
            guard let place = answer(lat: stop.lat, lon: stop.lon), let name = place.name else { continue }
            if StopNamer.needsName(stop) {
                Stored.write("setStopName") { try repository.setStopName(stopId: stop.id, name: name) }
            }
            StopNamer.storePlace(place, of: stop.id, repository: repository)
        }
    }

    private func lookUp(_ key: Key) async -> StopPlace {
        await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeStop(lat: key.lat, lon: key.lon) { place, _ in
                continuation.resume(returning: place)
            }
        }
    }
}
