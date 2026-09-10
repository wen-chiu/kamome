import AVKit
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
    @State private var player: AVPlayer?
    @State private var photosSaveState: PhotosSaveState = .idle
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    /// Captured at the tap, not during the render — see `RecapModel.startExport`.
    @Environment(\.colorScheme) private var colorScheme

    enum PhotosSaveState: Equatable {
        case idle
        case saving
        case saved
        case denied
        case failed(String)
    }

    init(tripId: String, session: TrackingSession) {
        _model = State(initialValue: RecapModel(
            tripId: tripId, config: session.config, repository: session.repository
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if case let .finished(_, fileURL, _) = model.phase {
                    finishedContent(fileURL: fileURL)
                } else {
                    exportForm
                }
            }
            .navigationTitle("recap_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("recap_done") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isRendering)
    }

    // MARK: - Export form (idle / rendering / failed)

    private var exportForm: some View {
        Form {
            Section {
                Toggle("recap_photos_toggle", isOn: $model.photosEnabled)
                    .disabled(model.isRendering)
                Picker("recap_format", selection: $model.format) {
                    Text("recap_format_mp4").tag(RecapModel.Format.mp4)
                    Text("recap_format_gif").tag(RecapModel.Format.gif)
                }
                .disabled(model.isRendering)
            } footer: {
                // The load-bearing sentence: photos ≠ chrome.
                Text("recap_photos_note")
            }

            if let shortfall = model.photoShortfall {
                Section {
                    Label("recap_photos_missing", systemImage: "icloud.slash")
                        .foregroundStyle(.orange)
                    Text(String.localizedStringWithFormat(
                        String(localized: "recap_photos_missing_detail"),
                        shortfall.missing, shortfall.requested
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            routingSection

            Section {
                switch model.phase {
                case .idle:
                    Button("recap_export") { model.startExport(appearance: RecapAppearance(colorScheme)) }

                case let .rendering(progress):
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress) {
                            Text("recap_rendering")
                        }
                        Button("recap_cancel", role: .cancel) { model.cancel() }
                    }

                case .finished:
                    EmptyView() // handled by finishedContent

                case let .failed(message):
                    Label("recap_failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("recap_export") { model.startExport(appearance: RecapAppearance(colorScheme)) }
                }
            }
        }
    }

    // MARK: - Finished: inline player + actions

    /// On finish the film plays immediately, inline, on this screen (Chiu
    /// 2026-09-05). Four actions: save to Photos / share / delete / export
    /// again. The render-time readout stays — it is the §4.5 budget readout.
    private func finishedContent(fileURL: URL) -> some View {
        VStack(spacing: 0) {
            // Inline player — starts immediately.
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
            }

            if case let .finished(_, _, renderSeconds) = model.phase {
                // Actual number, visible on device — this is the §4.5
                // render-budget readout (< 90 s bar).
                Text(String.localizedStringWithFormat(
                    String(localized: "recap_render_time"),
                    String(format: "%.1f", renderSeconds)
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            }

            // Action buttons
            VStack(spacing: 12) {
                // Save to Photos — explicit user tap, never automatic (§0).
                photosSaveButton(fileURL: fileURL)

                if case let .finished(film, _, _) = model.phase {
                    ShareLink(item: fileURL) {
                        Label("recap_share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("recap_film_delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog(
                        "recap_film_delete_confirm",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("recap_film_delete", role: .destructive) {
                            model.deleteFilm(film)
                            player = nil
                        }
                    }
                }

                Button("recap_export_again") {
                    player = nil
                    model.startExport(appearance: RecapAppearance(colorScheme))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            let newPlayer = AVPlayer(url: fileURL)
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private func photosSaveButton(fileURL: URL) -> some View {
        Button {
            saveToPhotos(fileURL: fileURL)
        } label: {
            switch photosSaveState {
            case .idle:
                Label("recap_save_to_photos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            case .saving:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .saved:
                Label("recap_saved_to_photos", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            case .denied:
                Label("recap_photos_access_denied", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(photosSaveState == .saving || photosSaveState == .saved)
    }

    /// `PHPhotoLibrary.requestAuthorization(for: .addOnly)` — NOT `.readWrite`.
    /// The app already holds read access for import, and conflating the two
    /// muddies D4 (Limited Photo Library), still open.
    ///
    /// Saving to the Photos library is an explicit user tap, never automatic
    /// (Chiu 2026-09-05). With iCloud Photos on, a write to the library
    /// uploads off-device — §0's decided exceptions are the Geoapify routing
    /// payloads and one user-initiated share. This tap is that share.
    private func saveToPhotos(fileURL: URL) {
        photosSaveState = .saving
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    photosSaveState = .denied
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        photosSaveState = .saved
                    } else {
                        photosSaveState = .failed(
                            error?.localizedDescription ?? String(localized: "recap_failed")
                        )
                    }
                }
            }
        }
    }

    /// Why the film's legs draw dashed, when there is a reason worth giving.
    ///
    /// **Four causes, one symptom** (2026-08-15). A dashed leg can mean no road
    /// route exists, the provider could not be reached, it refused for load, or
    /// the trip budget ran out — and only the first is the journey being drawn
    /// honestly. The other three are worth a retry, and used to be
    /// indistinguishable from it in the finished film. A fully routed film and a
    /// disabled endpoint say nothing at all: there is nothing to act on.
    @ViewBuilder
    private var routingSection: some View {
        if let routing = model.routing, routing.isWorthReporting {
            // How many legs draw dashed — the one number the copy uses. It sits
            // in the *headline* ("有 X 段還沒畫"), and only the rate-limit body
            // repeats it, so both strings are formatted with it and the three
            // bodies that do not mention it simply ignore the argument.
            let dashed = routing.attempted - routing.reconstructed
            Section {
                Label {
                    Text(String.localizedStringWithFormat(
                        String(localized: routingHeadlineKey(routing)), dashed
                    ))
                } icon: {
                    Image(systemName: routingSymbol(routing))
                }
                .foregroundStyle(routing.headline == .someLegsHaveNoRoad ? Color.secondary : Color.orange)
                Text(String.localizedStringWithFormat(
                    String(localized: routingDetailKey(routing)), dashed
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func routingHeadlineKey(_ report: RouteMatchReport) -> String.LocalizationValue {
        switch report.headline {
        case .providerUnreachable: return "recap_routing_unreachable"
        case .rateLimited: return "recap_routing_rate_limited"
        case .budgetExhausted: return "recap_routing_budget"
        case .someLegsHaveNoRoad, .disabled, .allRouted: return "recap_routing_no_road"
        }
    }

    private func routingDetailKey(_ report: RouteMatchReport) -> String.LocalizationValue {
        switch report.headline {
        case .providerUnreachable: return "recap_routing_unreachable_detail"
        case .rateLimited: return "recap_routing_rate_limited_detail"
        case .budgetExhausted: return "recap_routing_budget_detail"
        case .someLegsHaveNoRoad, .disabled, .allRouted: return "recap_routing_no_road_detail"
        }
    }

    /// A road that genuinely is not there is not a warning — it gets the map
    /// glyph and secondary colour, while the three retryable causes get the
    /// network glyph and the same orange the photo shortfall uses.
    private func routingSymbol(_ report: RouteMatchReport) -> String {
        switch report.headline {
        case .someLegsHaveNoRoad, .disabled, .allRouted: return "point.topleft.down.curvedto.point.bottomright.up"
        case .rateLimited, .budgetExhausted: return "clock.badge.exclamationmark"
        case .providerUnreachable: return "wifi.slash"
        }
    }
}
