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

/// S5 Export (P3 scope): photos toggle, MP4/GIF choice, progress, inline
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
                vehicleSection

                // Its own section so the note reads as the toggle's, not as a
                // caption under Format (S5 review item 4).
                Section {
                    Toggle("recap_photos_toggle", isOn: $model.photosEnabled)
                } footer: {
                    // The load-bearing sentence: photos ≠ chrome.
                    Text("recap_photos_note")
                }

                filmPhotosSection

                // After the stops: GIF is a minority choice and MP4 the default
                // (UX rule 2), so Format is the last setting, not the second.
                Section {
                    Picker("recap_format", selection: $model.format) {
                        Text("recap_format_mp4").tag(RecapModel.Format.mp4)
                        Text("recap_format_gif").tag(RecapModel.Format.gif)
                    }
                }
            }

            if model.photoShortfall != nil {
                Section { RecapPhotoShortfallNotice(model: model) }
            }
            if model.routing?.isWorthReporting == true {
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
                            Text(progress, format: .percent.precision(.fractionLength(0)))
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
    /// review item 3): "N stops · M photos", counts only (Chiu 2026-09-26).
    /// Read off the same plan the export composes and the list above draws, so
    /// it moves as stops go in and out. No duration: the timeline needs a
    /// composed trip, and composing waits on routing. With photo cards off the
    /// film shows none, so the photos half is not said.
    @ViewBuilder
    private var filmSummary: some View {
        if let filmPhotos {
            let stops = String.localizedStringWithFormat(
                String(localized: "recap_film_stop_count"), filmPhotos.filmStops.count
            )
            let photos = String.localizedStringWithFormat(
                String(localized: "recap_film_photo_count"), filmPhotos.filmPhotoCount
            )
            Text(verbatim: model.photosEnabled ? "\(stops) · \(photos)" : stops)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
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
            model.startExport(appearance: RecapAppearance(colorScheme))
        } label: {
            Label("recap_export", systemImage: "film")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
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

    /// Which subject the film draws. **Moved here from Trip Detail** (Chiu
    /// 2026-09-22): the choice only ever affected the film — nothing on the
    /// trip screen read it — so it belongs where the film is actually
    /// configured. A mid-render edit is safe (`RecapExportJob` snapshots the
    /// subject once at compose time); it is still hidden while rendering so
    /// the picker never reads as "this changes the film in progress".
    ///
    /// The plane is deliberately absent: the app picks it from the journey for
    /// a crossing, and choosing one for a road trip is not a feature.
    @ViewBuilder
    private var vehicleSection: some View {
        let subjects = model.pickableSubjects
        if subjects.count > 1 {
            Section("recap_vehicle_header") {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(subjects, id: \.id) { subject in
                                Button {
                                    model.chooseVehicle(subject.id)
                                } label: {
                                    vehicleChip(subject, isSelected: subject.id == model.vehicleId)
                                }
                                .buttonStyle(.plain)
                                .id(subject.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // **The chosen vehicle opens in view** (S5 review item 5).
                    // With a chip late in the row chosen, the sheet opened on
                    // the first three and nothing said which was selected.
                    // Centred, so its neighbours show and the row still reads
                    // as scrollable; on appear only — a tapped chip is in view.
                    .onAppear { proxy.scrollTo(model.vehicleId, anchor: .center) }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
            }
        }
    }

    private func vehicleChip(_ subject: VehicleSubject, isSelected: Bool) -> some View {
        // A subject with no thumbnail yet shows its name alone. Deliberately not
        // a grey box or a "missing image" glyph: those read as broken, and this
        // is not broken — the set works in a film and simply has no picture yet.
        // A chip that is only a name is an ordinary chip.
        return HStack(spacing: 6) {
            if let thumbnail = VehicleCatalog.thumbnail(id: subject.id) {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            }
            Text(subject.screenName)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
        .overlay(
            Capsule().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .clipShape(Capsule())
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
