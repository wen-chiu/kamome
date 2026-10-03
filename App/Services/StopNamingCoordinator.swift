import Foundation
import KamomeConfig
import KamomePersistence
import Observation

/// **One naming run per trip, and it outlives the screen that started it**
/// (#159, ADR 2026-10-01) — the same single-flight shape as
/// `RouteMatchCoordinator`.
///
/// `StopNamer` used to belong to `TripDetailModel`, so it died with the screen:
/// leaving Trip Detail on stop 10 of 26 dropped the queue, and coming back
/// started the wait again. Two screens on one trip ran two namers over the same
/// stops. The namer now lives here for as long as it has work, and a screen
/// that opens mid-run joins it.
///
/// What starts naming has not changed: a screen showing the trip asks. Only
/// who owns the run has.
@MainActor
@Observable
final class StopNamingCoordinator {
    static let shared = StopNamingCoordinator()

    /// How far naming has got, per trip with a run in flight.
    private(set) var progress: [String: StopNamer.Progress] = [:]

    private var namers: [String: StopNamer] = [:]
    /// Who hears each trip's progress, by the object that asked. Keyed so a
    /// screen that asks again replaces its own entry rather than adding one.
    private var listeners: [String: [ObjectIdentifier: (StopNamer.Progress) -> Void]] = [:]
    /// nil is the shipping geocoder (`StopNamer`'s default); a test passes a stub.
    private let geocoder: (() -> StopGeocoding)?

    init(geocoder: (() -> StopGeocoding)? = nil) {
        self.geocoder = geocoder
    }

    /// Names the trip's unnamed stops and fills the towns still missing, or
    /// joins the run already doing so. Returns at once; names land in the
    /// database. `onChange` is called on the main actor each time progress
    /// moves, until the run ends — hold `owner` weakly inside it.
    ///
    /// `first` are the stops to name ahead of the rest: the ones the film
    /// shows, so the film button waits only for them (Chiu 2026-10-01, #160).
    func start(
        tripId: String, stops: [StopRecord], first: Set<String> = [], repository: TripRepository,
        config: TrackingConfig.Geocode,
        for owner: AnyObject? = nil, onChange: ((StopNamer.Progress) -> Void)? = nil
    ) {
        let namer = namers[tripId] ?? StopNamer(config: config, repository: repository, geocoder: geocoder?())
        namers[tripId] = namer
        if let owner, let onChange { listeners[tripId, default: [:]][ObjectIdentifier(owner)] = onChange }

        // Cleared while stops are handed over: the first call below can run the
        // queue empty before the second has added its towns.
        namer.onDrained = nil
        let needy = stops.filter(StopNamer.needsName)
        let unnamed = needy.filter { first.contains($0.id) } + needy.filter { !first.contains($0.id) }
        if !unnamed.isEmpty {
            namer.nameUnnamedStops(unnamed) { [weak self] progress in
                self?.publish(progress, tripId: tripId)
            }
        }
        // After the hand-over, so a run joined mid-way is reordered as well.
        if !first.isEmpty { namer.prioritise(first) }
        // The film's HUD pill names the town (ADR 2026-09-24 (e)); stops named
        // before schema v9 are asked once, behind any naming. Each one that
        // lands is told to the listeners as well: its zone changes the day and
        // hour a screen is showing (ADR 2026-10-01).
        namer.fillMissingLocalities(stops) { [weak self, weak namer] in
            guard let namer else { return }
            self?.publish(namer.progress, tripId: tripId)
        }

        guard !namer.isIdle else {
            release(namer, tripId: tripId)
            return
        }
        namer.onDrained = { [weak self, weak namer] in
            guard let namer else { return }
            self?.release(namer, tripId: tripId)
        }
    }

    /// Whether stops are still being named for this trip.
    func isNaming(_ tripId: String) -> Bool {
        progress[tripId].map { $0.total > 0 && !$0.isFinished } ?? false
    }

    /// Whether any of these stops is still owed a name by this trip's run.
    func isNaming(_ tripId: String, anyOf stopIds: Set<String>) -> Bool {
        // Read so an observer is told when progress moves; the answer itself
        // is the namer's queue.
        guard isNaming(tripId), let namer = namers[tripId] else { return false }
        return !namer.pendingNameIds.isDisjoint(with: stopIds)
    }

    /// Names these stops ahead of the rest of a run in flight: the person put
    /// one into the film on the export sheet.
    func nameFirst(_ stopIds: Set<String>, tripId: String) {
        namers[tripId]?.prioritise(stopIds)
    }

    /// Stops the run before its next stop — the trip was deleted.
    func cancel(tripId: String) {
        guard let namer = namers[tripId] else { return }
        namer.cancel()
        if namer.isIdle { release(namer, tripId: tripId) }
    }

    private func publish(_ progress: StopNamer.Progress, tripId: String) {
        self.progress[tripId] = progress
        for listener in listeners[tripId, default: [:]].values { listener(progress) }
    }

    /// Lets go of a finished run. Checked against the namer itself, so a run
    /// that ends late cannot release the one that replaced it.
    private func release(_ namer: StopNamer, tripId: String) {
        guard namers[tripId] === namer else { return }
        namers[tripId] = nil
        listeners[tripId] = nil
        progress[tripId] = nil
    }
}
