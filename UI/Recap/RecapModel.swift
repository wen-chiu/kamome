import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import Observation

/// Backs S5. **This model no longer owns the export** (Chiu 2026-09-10, Phase 4
/// closeout step 2).
///
/// It used to run the render itself, which is why closing the sheet destroyed
/// the film: the model was `@State` inside `RecapView`, and Done called
/// `cancel()` on the way out. The pipeline is now `RecapExportJob`, owned and
/// single-flighted by `RecapExportCoordinator.shared`, which outlives every
/// view. What is left here is one trip's view of that coordinator, plus the two
/// settings the *next* export will be started with.
///
/// So this type is cheap and disposable on purpose: a new one is built each time
/// the sheet opens, and it finds the render already in progress.
@Observable
@MainActor
final class RecapModel {
    typealias Format = RecapExportFormat

    enum Phase: Equatable {
        case idle
        case rendering(progress: Double)
        /// A finished film is a record, not a bare URL. The record carries the
        /// relative path; the resolved URL is passed alongside it so the view can
        /// play the file without resolving again.
        case finished(film: FilmRecord, fileURL: URL)
        case failed(message: String)
    }

    /// Photo overlays only (decisions.md 2026-07-18 recap-chrome, Chiu):
    /// off removes stop photo cards; title/end cards always render.
    ///
    /// ⚠️ These two are what the **next** export is started with. While one is
    /// running, `photosEnabled` and `format` below read from the running request
    /// instead, so a sheet reopened mid-render shows the settings the film in
    /// flight is actually using rather than this fresh model's defaults.
    private var requestedPhotosEnabled = true
    private var requestedFormat: Format = .mp4

    /// Set when a start was refused because a **different** trip is rendering.
    /// One export at a time is a hard rule (`RecapExportCoordinator`); this is
    /// how the screen says so.
    private(set) var busyTripId: String?

    /// Which subject this trip's film draws. Loaded once at init, not read
    /// live off the trip: this model is rebuilt each time the sheet opens
    /// (see the type doc), so a stale value cannot outlive one presentation.
    private(set) var vehicleId: String

    let tripId: String
    private let config: TrackingConfig
    private let repository: TripRepository
    private let coordinator: RecapExportCoordinator

    init(
        tripId: String, config: TrackingConfig, repository: TripRepository,
        coordinator: RecapExportCoordinator = .shared
    ) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
        self.coordinator = coordinator
        vehicleId = Stored.read("detail") { try repository.detail(tripId: tripId) }?.trip.vehicleId
            ?? VehicleCatalog.defaultSubjectId
    }

    // MARK: - Vehicle

    /// What the picker offers: every selectable subject, plus this trip's own
    /// even when it is not selectable — a picker must always be able to show
    /// what is currently set, including a subject the app chose itself.
    ///
    /// **Moved here from Trip Detail** (Chiu 2026-09-22): the choice only ever
    /// affects the film — nothing on the trip screen read it — so it belongs
    /// where the film is actually configured, not sitting permanently on the
    /// trip's own page.
    var pickableSubjects: [VehicleSubject] {
        let selectable = VehicleCatalog.selectableSubjects
        guard !selectable.contains(where: { $0.id == vehicleId }),
              let current = VehicleCatalog.subject(id: vehicleId)
        else { return selectable }
        return [current] + selectable
    }

    /// Writes the choice to the trip and remembers it for the next new trip's
    /// default. A column write, same as before the move — it never costs a
    /// re-import, and the export job reads it at render time.
    /// The next film's photographs, stop by stop, and the person's choices
    /// over them (ADR 2026-09-24) — the export composes exactly this plan.
    func filmPhotoChoices() -> FilmPhotoChoices {
        FilmPhotoChoices(tripId: tripId, config: config, repository: repository)
    }

    func chooseVehicle(_ id: String) {
        Stored.write("setTripVehicle") { try repository.setTripVehicle(tripId: tripId, vehicleId: id) }
        LastVehicleChoice.remember(id)
        vehicleId = id
    }

    // MARK: - What the screen draws

    var photosEnabled: Bool {
        get { running?.request.photosEnabled ?? requestedPhotosEnabled }
        set { requestedPhotosEnabled = newValue }
    }

    var format: Format {
        get { running?.request.format ?? requestedFormat }
        set { requestedFormat = newValue }
    }

    var phase: Phase {
        if let running { return .rendering(progress: running.fraction) }
        switch coordinator.outcome(tripId: tripId) {
        case let .finished(film, fileURL): return .finished(film: film, fileURL: fileURL)
        case let .failed(message): return .failed(message: message)
        case .cancelled, .none: return .idle
        }
    }

    var isRendering: Bool { running != nil }

    /// What road reconstruction managed for this trip, surfaced for the same
    /// reason `photoShortfall` is (2026-08-15): a film whose legs draw dashed
    /// looks like a rendering bug, and the four reasons it can happen — no road
    /// route exists, the provider could not be reached, it refused for load, or
    /// the budget ran out — need four different responses from the user. Only
    /// one of them means "this is simply what the journey looks like".
    ///
    /// Read from the finished film's findings once the run is over, so the
    /// finished screen can still say why — see `RecapExportCoordinator.Findings`.
    var routing: RouteMatchReport? {
        running?.routing ?? coordinator.findings(tripId: tripId)?.routing
    }

    /// Set when warming could not load every deck photo — see
    /// `PhotoLibraryPhotoResolver.WarmSummary`. Surfaced rather than swallowed:
    /// the symptom is blank cards in a finished film, which reads as a rendering
    /// bug rather than as photos that are not on this device.
    var photoShortfall: PhotoLibraryPhotoResolver.WarmSummary? {
        running?.photoShortfall ?? coordinator.findings(tripId: tripId)?.photoShortfall
    }

    /// Set while photos that live only in iCloud are being downloaded for the
    /// film, ahead of the render. nil when every photo the film needs is already
    /// on the device — the common case, and the one that shows no extra UI.
    var photoPreload: PhotoLibraryPhotoResolver.PreloadProgress? { running?.photoPreload }

    private var running: RecapExportCoordinator.Running? {
        coordinator.running(tripId: tripId)
    }

    // MARK: - Actions

    /// Starts the render, or joins the one already in flight for this trip.
    ///
    /// **`appearance` is captured by the caller at the tap**, not read here.
    /// This is the composition boundary in the sense `Docs/decisions.md`
    /// 2026-08-15 means it: the place where a trip becomes *a specific film*. The
    /// ADR requires export variation to enter as an explicit value chosen here
    /// and held constant, never sampled from the environment while rendering —
    /// written for the photo-selection seed, and binding on this for the same
    /// reason. The appearance is ambient device state, so left unbound it would
    /// be exactly the coin toss the ADR names: a film that changes if the user
    /// toggles dark mode mid-render, and a failing golden frame nobody can
    /// reproduce. It arrives as a parameter from `RecapView`, which reads
    /// `@Environment(\.colorScheme)` on the main actor at the moment the button
    /// is pressed, and travels into `RecapExportRequest` unchanged.
    func startExport(appearance: RecapAppearance) {
        let request = RecapExportRequest(
            tripId: tripId,
            photosEnabled: requestedPhotosEnabled,
            format: requestedFormat,
            appearance: appearance
        )
        let job = RecapExportJob(request: request, config: config, repository: repository)
        switch coordinator.start(request: request, job: job) {
        case .started, .joined:
            busyTripId = nil
        case let .refused(busyTripId):
            self.busyTripId = busyTripId
        }
    }

    /// **An explicit user action, and only that.** Dismissing the export screen
    /// no longer cancels — that is the whole of Phase 4 closeout step 2.
    func cancel() {
        coordinator.cancel(tripId: tripId)
    }

    /// Returns the screen to idle so a new export can be configured. Never
    /// touches a run in flight. **It does not start one** (2026-09-25): it used
    /// to, which left no way to change the vehicle or the photos between films
    /// short of deleting the one just made. Export is one more tap, on the form.
    func exportAgain() {
        coordinator.clearOutcome(tripId: tripId)
    }

    /// Deletes a film's row and its file. Called from the finished screen's
    /// delete action.
    func deleteFilm(_ film: FilmRecord) {
        do {
            try repository.deleteFilm(filmId: film.id)
            FilmStore.deleteFile(relativePath: film.relativePath)
            coordinator.clearOutcome(tripId: tripId)
        } catch {
            KamomeLog.recap.error("film deletion failed: \(error)")
        }
    }
}
