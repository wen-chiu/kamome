import Foundation
import KamomeConfig
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

    /// Asks about each place with no answer yet, in order, one at a time.
    /// `onAnswer` runs after each answer lands. Replaces any run still going.
    func name(_ places: [JourneyItinerary.Place], onAnswer: @escaping () -> Void) {
        task?.cancel()
        let pending = places.map { Key(lat: $0.lat, lon: $0.lon) }.filter { answers[$0] == nil }
        guard !pending.isEmpty else { return }
        task = Task { [weak self] in
            for key in pending {
                guard !Task.isCancelled, let self else { return }
                guard self.answers[key] == nil else { continue }
                let place = await self.lookUp(key)
                if place.name != nil {
                    self.answers[key] = place
                    onAnswer()
                } else {
                    // Left for S3, whose namer tries again and says why.
                    KamomeLog.geocode.notice("preview stop naming produced no name; S3 will ask")
                }
            }
        }
    }

    /// The preview has closed.
    func cancel() {
        task?.cancel()
        task = nil
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
