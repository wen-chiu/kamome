import AVKit
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import Photos
import SwiftUI

/// The film's appearance, read from SwiftUI's environment.
///
/// `@Environment(\.colorScheme)` rather than `UITraitCollection.current`: the
/// trait collection is only meaningful inside a view update and is main-actor
/// besides, so reading it from the model — let alone from the detached render
/// loop — is the ambient read `Docs/decisions.md` 2026-08-15 forbids. The
/// environment value is the supported read of the same state and additionally
/// honours a `.preferredColorScheme` override in the hierarchy, which the trait
/// collection would not.
private extension RecapAppearance {
    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

/// S5 Export (P3 scope): photos toggle, progress, inline
/// playback, share, save to Photos, delete. The toggle copy must make clear
/// it controls photo overlays only — title and end cards always render
/// (decisions.md 2026-07-18 recap-chrome, Chiu).
struct RecapView: View {
    @State private var model: RecapModel
    /// The next film's photographs; built once when the sheet appears.
    @State private var filmPhotos: FilmPhotoChoices?
    @Environment(\.dismiss) private var dismiss
    /// Captured at the tap, not during the render — see `RecapModel.startExport`.
    @Environment(\.colorScheme) private var colorScheme

    init(tripId: String, session: TrackingSession) {
        _model = State(initialValue: RecapModel(
            tripId: tripId, config: session.config, repository: session.repository
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if case let .finished(_, fileURL) = model.phase {
                    RecapFinishedView(model: model, fileURL: fileURL)
                } else {
                    exportForm
                        .onAppear { if filmPhotos == nil { filmPhotos = model.filmPhotoChoices() } }
                        .onAppear { Self.startDemoExportIfAsked(model, RecapAppearance(colorScheme), filmPhotos?.length) }
                        // Analysis landing while the sheet is open changes the
                        // app's pick; the list must show the one the export uses.
                        .onChange(of: PhotoAnalysisCoordinator.shared.finishedRuns[model.tripId]) {
                            filmPhotos?.reload()
                        }
                }
            }
            .navigationTitle("recap_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // **Leaving no longer cancels** (Chiu 2026-09-10). This
                    // button used to call `model.cancel()` on the way out, which
                    // is why a render of a minute or more pinned the user here.
                    // The export belongs to `RecapExportCoordinator` now and
                    // outlives this screen; cancelling is the Cancel button
                    // below, and nothing else.
                    Button(model.isRendering ? "recap_back" : "recap_done") { dismiss() }
                }
            }
        }
        // ⚠️ `interactiveDismissDisabled(model.isRendering)` used to live here.
        // It was the only thing preventing a half-written file and a leaked
        // background assertion while the model owned the render, and it could
        // only be removed **together with** the coordinator that made leaving
        // safe — removing it on its own is the regression, not the fix.
    }

    // MARK: - Export form (idle / rendering / failed)

    private var exportForm: some View {
        Form {
            // **The settings fold away while rendering** (S5 review 2026-09-25,
            // item 2). They used to stay on screen disabled, which is a form that
            // looks editable and is not; the film in flight has already chosen.
            if !model.isRendering {
                settingsSection

                // Its own section so the note reads as the toggle's, not as a
                // caption under the settings (S5 review item 4).
                Section {
                    Toggle("recap_photos_toggle", isOn: $model.photosEnabled)
                } footer: {
                    // The load-bearing sentence: photos ≠ chrome.
                    Text("recap_photos_note")
                }

                filmPhotosSection
            }
            if model.isRendering { ExportGullSection(progress: model.drawingFraction, caption: model.gullCaption) }

            if model.photoShortfall != nil {
                Section { RecapPhotoShortfallNotice(model: model) }
            }
            if model.routing?.isWorthReporting == true, model.gullCaption == nil {
                Section { RecapRoutingNotice(model: model) }
            }
            busySection
        }
        // **The action is pinned, not scrolled to** (Chiu 2026-09-25). As the
        // form's last section, Export sat below every stop's photo row — on a
        // trip of any size it was off screen, and nothing on the first screen
        // said the film was one tap away. The bar stays visible over the form
        // in every phase that has one: idle, rendering and failed.
        .safeAreaInset(edge: .bottom) { exportBar }
    }

    /// Export / progress / retry, docked to the bottom of the form.
    @ViewBuilder
    private var exportBar: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            switch model.phase {
            case .idle:
                filmSummary
                exportButton
                FilmNamingNote(tripId: model.tripId, stopIds: filmStopIds)

            case let .rendering(progress):
                if let preload = model.photoPreload {
                    photoPreloadProgress(preload)
                } else {
                    // A 1–3 minute wait owes a name and a number (S5 review
                    // item 2). The number only while drawing: `progress`
                    // measures frames, so before them it would sit at 0%.
                    ProgressView(value: progress) {
                        Text(stageTitle(model.stage ?? .findingRoads))
                    } currentValueLabel: {
                        if model.stage == .drawing {
                            Text(verbatim: Self.drawingProgress(progress, timeLeft: model.timeLeft))
                                .monospacedDigit()
                        }
                    }
                }
                // The promise, and its exact bounds (Chiu 2026-09-10):
                // leave this SCREEN, stay in the APP. `AVAssetWriter`
                // cannot resume across process death, so this copy may
                // never say the export continues in the background —
                // `ExportLifecycleGuard` is what makes the narrower
                // promise true, and `LocalizationTests` holds the copy
                // to it in both languages.
                Text("recap_rendering_leave_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("recap_cancel", role: .cancel) { model.cancel() }
                    .frame(maxWidth: .infinity)

            case .finished:
                EmptyView() // handled by finishedContent

            case let .failed(message):
                Label("recap_failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                filmSummary
                exportButton
            }
        }
        content
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }

    /// **What the tap will make, said before it** (DESIGNER.md UX rule 3, S5
    /// review item 3): "N stops · M photos · about 1:28". Read off the same
    /// plan the export composes and the list above draws, so it moves as stops
    /// go in and out. With photo cards off the film shows none, so the photos
    /// half is not said.
    ///
    /// **The length is said now** (Chiu 2026-09-27, reopening ADR 2026-09-26
    /// (c) item 7). It was left out because the timeline needs a composed trip;
    /// the length does not — it is the timeline's own plan over these decks
    /// (`RecapComposer.estimatedFilmS`), then the export's own timeline once it
    /// is measured (Chiu 2026-09-29). "About", because a trip still routing is
    /// measured on straight legs, and the export routes before it builds.
    @ViewBuilder
    private var filmSummary: some View {
        if let filmPhotos {
            let stops = String.localizedStringWithFormat(
                String(localized: "recap_film_stop_count"), filmPhotos.filmStops.count
            )
            let photos = String.localizedStringWithFormat(
                String(localized: "recap_film_photo_count"), filmPhotos.filmPhotoCount
            )
            let length = String.localizedStringWithFormat(
                String(localized: "recap_film_length_estimate"),
                Self.clock(filmPhotos.estimatedFilmS(photosEnabled: model.photosEnabled))
            )
            let counts = model.photosEnabled ? "\(stops) · \(photos)" : stops
            Text(verbatim: "\(counts) · \(length)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// **How the film is made, in one place** (Chiu 2026-10-09): length and
    /// vehicle as rows above the stops, so the settings read as one short block
    /// and the list below is only *what* the film shows. The format row is gone
    /// with the GIF (Chiu 2026-10-10): every film is an MP4.
    private var settingsSection: some View {
        Section {
            lengthRow
            // The plane is deliberately absent from the picker: the app picks it
            // from the journey for a crossing (`VehiclePickerLayout`).
            if model.pickableSubjects.count > 1 { VehicleRow(model: model) }
        } header: {
            Text("recap_settings_header")
        } footer: {
            lengthFooter
        }
    }

    /// **Short or standard** (Chiu 2026-09-27). Short is the default and fits
    /// a Reel whole; standard is the film the trip earns from its size, at most
    /// 300 s. Hidden when both make the same film — a small trip has nothing to
    /// choose — unless there is a warning to give: the person's own additions
    /// carried the film past its ceiling, which the app never cuts for them.
    @ViewBuilder
    private var lengthRow: some View {
        if let filmPhotos, showsLength(filmPhotos) {
            HStack {
                Text("recap_length_header")
                Spacer()
                Picker("recap_length_header", selection: Binding(
                    get: { filmPhotos.length }, set: { length in withAnimation { filmPhotos.choose(length) } }
                )) {
                    Text("recap_length_short").tag(FilmLength.short)
                    Text("recap_length_standard").tag(FilmLength.standard)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var lengthFooter: some View {
        if let filmPhotos, showsLength(filmPhotos) {
            let ceiling = Self.clock(filmPhotos.ceilingS)
            if filmPhotos.isOverCeiling(photosEnabled: model.photosEnabled) {
                let estimate = filmPhotos.estimatedFilmS(photosEnabled: model.photosEnabled)
                Text(verbatim: String.localizedStringWithFormat(
                    String(localized: "recap_length_over"), Self.clock(estimate), ceiling
                ))
                .foregroundStyle(.orange)
            } else {
                let footer: String.LocalizationValue = filmPhotos.length == .short
                    ? "recap_length_short_footer" : "recap_length_standard_footer"
                Text(verbatim: String.localizedStringWithFormat(String(localized: footer), ceiling))
            }
        }
    }

    private func showsLength(_ filmPhotos: FilmPhotoChoices) -> Bool {
        filmPhotos.lengthsDiffer || filmPhotos.isOverCeiling(photosEnabled: model.photosEnabled)
    }

    /// The stage's name. The two later ones reuse the sentences the screen
    /// already said at those moments.
    private func stageTitle(_ stage: RecapExportStage) -> LocalizedStringKey {
        switch stage {
        case .findingRoads: return "recap_stage_roads"
        case .preparingPhotos: return "recap_photos_preparing"
        case .drawing: return "recap_rendering"
        }
    }

    private var exportButton: some View {
        Button {
            model.startExport(
                appearance: RecapAppearance(colorScheme), length: filmPhotos?.length ?? FilmLengthChoice.current()
            )
        } label: {
            Label("recap_export", systemImage: "film")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .waitsForNaming(tripId: model.tripId, of: filmStopIds)
    }

    /// Which stops the film presents and what each shows, before it is
    /// rendered (ADR 2026-09-24, Chiu 2026-09-25) — `FilmStopsSections`.
    /// Hidden while rendering, with the rest of the settings — `exportForm`.
    @ViewBuilder
    private var filmPhotosSection: some View {
        if model.photosEnabled, let filmPhotos {
            FilmStopsSections(choices: filmPhotos)
        }
    }

    /// The download phase before the render — only shown when some of the film's
    /// photos live in iCloud only. `n / total` counts those photos alone, never
    /// the ones already on the device.
    private func photoPreloadProgress(_ preload: PhotoLibraryPhotoResolver.PreloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("recap_photos_preparing")
            ProgressView(value: preload.fraction) {
                Text("recap_photos_downloading")
            } currentValueLabel: {
                Text(verbatim: "\(min(preload.completed + 1, preload.total)) / \(preload.total)")
            }
        }
    }

    /// **One export at a time, said out loud.** With a back button the user can
    /// leave a running export, open another trip and tap Export there; two
    /// `AVAssetWriter`s and two snapshotter streams on a phone is a crash rather
    /// than a slowdown, so `RecapExportCoordinator` refuses. A refusal the screen
    /// swallowed would look exactly like a dead button (`Arch.md` §6).
    @ViewBuilder
    private var busySection: some View {
        if model.busyTripId != nil {
            Section {
                Label("recap_export_busy", systemImage: "hourglass")
                    .foregroundStyle(.orange)
                Text("recap_export_busy_detail")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Out of the struct's body for SwiftLint's 250-line limit; nothing else moved.
extension RecapView {
    /// The stops the film presents now, for the naming gate (`FilmNamingNote`).
    fileprivate var filmStopIds: Set<String> { Set(filmPhotos?.filmStops.map(\.id) ?? []) }

    /// Film seconds as the clock a video player shows: 1:28, 3:32.
    static func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
    }
}
