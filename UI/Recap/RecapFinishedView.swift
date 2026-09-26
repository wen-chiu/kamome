import AVKit
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import Photos
import SwiftUI

/// The export sheet once the film exists: it plays inline, and the actions sit
/// under it. Split out of `RecapView` (arch review 2026-09-26, round 2): the
/// sheet had reached 549 lines while `UI/` went unlinted, and this screen owns
/// state — the player, the save — that the form never touched.
struct RecapFinishedView: View {
    let model: RecapModel
    let fileURL: URL
    @State private var player: AVPlayer?
    @State private var photosSaveState: PhotosSaveState = .idle
    @State private var showDeleteConfirmation = false

    enum PhotosSaveState: Equatable {
        case idle
        case saving
        case saved
        case denied
        /// The reason is logged, never shown — `PHPhotosErrorDomain 3302` is
        /// not a sentence (DESIGNER.md UX rule 5).
        case failed
    }

    /// On finish the film plays immediately, inline, on this screen (Chiu
    /// 2026-09-05). Four actions: save to Photos / share / delete / export
    /// again. The render-time readout stays — it is the §4.5 budget readout,
    /// and it stays in Release (Chiu 2026-09-26).
    ///
    /// **Completion is a moment** (DESIGNER.md UX rule 6, ADR 2026-09-26 (c)).
    /// The four actions are unchanged; only their weight is: Save and Share are
    /// the pair, Export again is a text button, and Delete lives in the ⋯ menu,
    /// still behind its confirmation — it was a full-width red button as heavy
    /// as Share.
    var body: some View {
        VStack(spacing: 0) {
            // Chiu's copy. Through `String`, not `Text("key")`: a key is parsed
            // as Markdown, and the zh title's two `~` became a strikethrough.
            Text(String(localized: "recap_finished_title"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 8)
            preview
            renderReadout
            // What the run found, kept past its end: without this a film with
            // blank cards or dashed legs came back with no reason given.
            if model.photoShortfall != nil || model.routing?.isWorthReporting == true {
                VStack(alignment: .leading, spacing: 6) {
                    RecapPhotoShortfallNotice(model: model)
                    RecapRoutingNotice(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            actions
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("recap_film_delete", systemImage: "trash")
                    }
                } label: {
                    Label("recap_more_actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "recap_film_delete_confirm",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("recap_film_delete", role: .destructive) {
                if case let .finished(film, _) = model.phase {
                    model.deleteFilm(film)
                    player = nil
                }
            }
        }
        .onAppear {
            guard !isGIF else { return }
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
    private var preview: some View {
        // Inline preview — starts immediately. A GIF is not a video:
        // `AVPlayer` shows a struck-through play glyph for one, so it gets
        // its own view (2026-09-25).
        if isGIF {
            AnimatedGIFView(url: fileURL)
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
        } else if let player {
            VideoPlayer(player: player)
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
        }
    }

    @ViewBuilder
    private var renderReadout: some View {
        if case let .finished(film, _) = model.phase, let renderSeconds = film.renderSeconds {
            // Actual number, visible on device — this is the §4.5
            // render-budget readout (< 90 s bar). Read off the stored
            // record rather than off the phase, so it is the same number
            // whether the film finished with this screen open or not.
            Text(String.localizedStringWithFormat(
                String(localized: "recap_render_time"),
                String(format: "%.1f", renderSeconds)
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Save to Photos — explicit user tap, never automatic (§0).
                photosSaveButton

                ShareLink(item: fileURL) {
                    Label("recap_share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            // Said beside the buttons, not inside one: a sentence on a
            // prominent button reads as the button's action.
            if photosSaveState == .failed {
                Text("recap_save_failed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Back to the form, not straight into a render: the next film
            // may want a different vehicle or different photos.
            Button("recap_export_again") {
                player = nil
                photosSaveState = .idle
                model.exportAgain()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var photosSaveButton: some View {
        Button {
            saveToPhotos()
        } label: {
            switch photosSaveState {
            case .idle, .failed:
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
    private func saveToPhotos() {
        photosSaveState = .saving
        let savesAsPhoto = isGIF
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    photosSaveState = .denied
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                // A GIF goes in as a photo — Photos plays an animated GIF — and
                // the video request refuses it (`PHPhotosErrorDomain` 3302).
                if savesAsPhoto {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: fileURL, options: nil)
                } else {
                    PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
            } completionHandler: { success, error in
                if let error {
                    let nsError = error as NSError
                    KamomeLog.recap.error(
                        "save to Photos failed: \(nsError.domain, privacy: .public) · \(nsError.code, privacy: .public)"
                    )
                }
                Task { @MainActor in
                    photosSaveState = success ? .saved : .failed
                }
            }
        }
    }

    private var isGIF: Bool {
        fileURL.pathExtension.lowercased() == RecapExportFormat.gif.rawValue
    }
}
