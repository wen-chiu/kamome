import CoreLocation
import Foundation

/// What one Apple lookup answered: every placemark field a caller reads. A
/// plain value, so the gate below can be driven by a stub in tests —
/// `CLPlacemark` has no public initialiser.
struct GeocodedPlace: Equatable, Sendable {
    var name: String?
    var thoroughfare: String?
    var subLocality: String?
    var locality: String?
    var administrativeArea: String?
    var country: String?
    /// ISO 3166-1 alpha-2.
    var countryCode: String?
    var inlandWater: String?
    var ocean: String?
    var areasOfInterest: [String]?
    /// The placemark's time zone identifier.
    var timeZone: String?
}

/// **The one door to Apple's geocoder** (#159, ADR 2026-10-01).
///
/// Apple rate-limits reverse geocoding per app, not per caller. Three callers
/// used to throttle only themselves — `StopNamer`, Journey Discovery's card
/// naming and `TripJourneyNaming` — so opening a journey from Discovery could
/// send about twice what `geocode.min_interval_s` was written to allow, and a
/// refused lookup is a stop the film calls "Unnamed stop".
///
/// Every shipping lookup now waits its turn here: one request at a time, the
/// next no sooner than its `minIntervalS` after the last one **finished**
/// (answered or failed — a failure costs the throttle too, `GeocodePolicy`).
/// When several wait, the highest `Priority` goes first: stop names hold the
/// film button, a card's title holds nothing.
///
/// Two asks for the same coordinate that are waiting or in flight together
/// share one request. Coordinates are held in memory for that long and no
/// longer, and are never logged (§0).
@MainActor
final class GeocodeGate {
    /// Ascending: a higher case is served first.
    enum Priority: Int, Comparable {
        /// A Journey Discovery card's title.
        case card
        /// A new trip's place and flag for Home (`TripJourneyNaming`).
        case tripFlag
        /// A stop's name, town and zone (`StopNamer`).
        case stop

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Answer: Sendable {
        /// nil when nothing came back.
        let place: GeocodedPlace?
        let error: Error?
    }

    typealias Lookup = @MainActor (_ lat: Double, _ lon: Double) async -> Answer

    /// The gate every shipping geocoder goes through.
    static let shared: GeocodeGate = {
        let apple = AppleGeocoder()
        return GeocodeGate { lat, lon in await apple.place(lat: lat, lon: lon) }
    }()

    private struct Request {
        let lat: Double
        let lon: Double
        var priority: Priority
        let minIntervalS: Double
        var waiters: [CheckedContinuation<Answer, Never>]

        func isFor(lat: Double, lon: Double) -> Bool { self.lat == lat && self.lon == lon }
    }

    private let lookup: Lookup
    /// In arrival order; the next one served is the first of the highest priority.
    private var waiting: [Request] = []
    private var inFlight: Request?
    private var lastFinished: ContinuousClock.Instant?
    private var wake: Task<Void, Never>?
    /// Asks received so far, joined ones included. A test waits on it to know
    /// an ask has reached the line before it makes the next.
    private(set) var requestCount = 0

    init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    /// Resolves one coordinate, after waiting for its turn.
    func place(lat: Double, lon: Double, priority: Priority, minIntervalS: Double) async -> Answer {
        await withCheckedContinuation { continuation in
            requestCount += 1
            if inFlight?.isFor(lat: lat, lon: lon) == true {
                inFlight?.waiters.append(continuation)
                return
            }
            if let index = waiting.firstIndex(where: { $0.isFor(lat: lat, lon: lon) }) {
                waiting[index].waiters.append(continuation)
                waiting[index].priority = max(waiting[index].priority, priority)
            } else {
                waiting.append(Request(
                    lat: lat, lon: lon, priority: priority, minIntervalS: minIntervalS, waiters: [continuation]
                ))
            }
            pump()
        }
    }

    /// Starts the next request if none is in flight and the throttle allows it;
    /// otherwise makes sure something calls back when it does.
    private func pump() {
        guard inFlight == nil,
              let best = waiting.map(\.priority).max(),
              let index = waiting.firstIndex(where: { $0.priority == best })
        else { return }
        let request = waiting[index]
        if let lastFinished {
            let ready = lastFinished + .seconds(request.minIntervalS)
            if ContinuousClock.now < ready {
                // The choice is made again when the wait is over, so a stop that
                // asks meanwhile still goes ahead of a card that asked first.
                wake?.cancel()
                wake = Task { [weak self] in
                    try? await Task.sleep(until: ready, clock: .continuous)
                    guard !Task.isCancelled else { return }
                    self?.pump()
                }
                return
            }
        }
        waiting.remove(at: index)
        inFlight = request
        Task { [weak self, lookup] in
            let answer = await lookup(request.lat, request.lon)
            self?.finish(answer)
        }
    }

    private func finish(_ answer: Answer) {
        let waiters = inFlight?.waiters ?? []
        inFlight = nil
        lastFinished = .now
        for waiter in waiters { waiter.resume(returning: answer) }
        pump()
    }
}

/// The Apple call itself: `CLGeocoder`, honouring the device locale so place
/// names come back in the user's language (§1.7). One instance is enough —
/// the gate never runs two lookups at once.
@MainActor
private final class AppleGeocoder {
    private let geocoder = CLGeocoder()

    func place(lat: Double, lon: Double) async -> GeocodeGate.Answer {
        do {
            let placemark = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first
            return GeocodeGate.Answer(place: placemark.map { GeocodedPlace($0) }, error: nil)
        } catch {
            return GeocodeGate.Answer(place: nil, error: error)
        }
    }
}

private extension GeocodedPlace {
    init(_ placemark: CLPlacemark) {
        self.init(
            name: placemark.name,
            thoroughfare: placemark.thoroughfare,
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            countryCode: placemark.isoCountryCode,
            inlandWater: placemark.inlandWater,
            ocean: placemark.ocean,
            areasOfInterest: placemark.areasOfInterest,
            timeZone: placemark.timeZone?.identifier
        )
    }
}
