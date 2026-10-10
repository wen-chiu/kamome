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
    /// Save and Share are the pair; Delete lives in the ⋯ menu, still behind
    /// its confirmation.
    ///
    /// **The film is the screen** (Chiu 2026-10-02, ADR
    /// 2026-10-02-the-finished-screen-is-the-film). Everything that is not the
    /// film gives up height to it: the readout and an honest "no road" share
    /// one caption line, and Export again joins Delete in ⋯. A run that went
    /// wrong in a way another export fixes still says so in full, with Export
    /// again beside it.
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
            caption
            // What the run found, kept past its end: without this a film with
            // blank cards or dashed legs came back with no reason given.
            if needsAnotherExport {
                VStack(alignment: .leading, spacing: 6) {
                    RecapPhotoShortfallNotice(model: model)
                    if routingNeedsAnotherExport { RecapRoutingNotice(model: model) }
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
                    Button {
                        exportAgain()
                    } label: {
                        Label("recap_export_again", systemImage: "arrow.counterclockwise")
                    }
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

    /// A dashed leg the provider could not reach, was too busy for or ran out
    /// of time on — unlike a leg with no road, another export can draw it.
    private var routingNeedsAnotherExport: Bool {
        guard let routing = model.routing, routing.isWorthReporting else { return false }
        return routing.headline != .someLegsHaveNoRoad
    }

    private var needsAnotherExport: Bool {
        model.photoShortfall != nil || routingNeedsAnotherExport
    }

    @ViewBuilder
    private var preview: some View {
        // Inline preview — starts immediately. A GIF made before GIF export was
        // removed is not played in the app (Chiu 2026-10-10): `AVPlayer` would
        // show a struck-through play glyph, so it gets no preview at all and
        // keeps share, save and delete.
        if let player {
            VideoPlayer(player: player)
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
    }

    /// One quiet line under the film: "Rendered in 324.8 s · 2 legs have no
    /// road". The readout is the §4.5 render-budget readout (< 90 s bar), read
    /// off the stored record rather than off the phase, so it is the same
    /// number whether the film finished with this screen open or not.
    ///
    /// A leg with no road is the film drawn honestly, not a fault, so it is a
    /// fact here and no more — the sentence explaining the dashes was said
    /// while the film rendered, and the film shows them.
    @ViewBuilder
    private var caption: some View {
        let parts = [renderReadout, noRoadHeadline].compactMap { $0 }
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var renderReadout: String? {
        guard case let .finished(film, _) = model.phase, let renderSeconds = film.renderSeconds else { return nil }
        return String.localizedStringWithFormat(
            String(localized: "recap_render_time"),
            String(format: "%.1f", renderSeconds)
        )
    }

    private var noRoadHeadline: String? {
        guard let routing = model.routing, routing.isWorthReporting,
              routing.headline == .someLegsHaveNoRoad else { return nil }
        return RecapRoutingNotice.headline(routing)
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
            // The pair is one row of one height: a label that wrapped made
            // Save taller than Share (Chiu 2026-10-01).
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .controlSize(.large)
            // Said beside the buttons, not inside one: a sentence on a
            // prominent button reads as the button's action.
            if let saveNote {
                Text(saveNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // On screen only when the run says another export would help;
            // otherwise it is in ⋯. Back to the form, not straight into a
            // render: the next film may want a different vehicle or photos.
            if needsAnotherExport {
                Button("recap_export_again") { exportAgain() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var saveNote: LocalizedStringKey? {
        switch photosSaveState {
        case .failed: return "recap_save_failed"
        case .denied: return "recap_photos_access_denied"
        case .idle, .saving, .saved: return nil
        }
    }

    private func exportAgain() {
        player = nil
        photosSaveState = .idle
        model.exportAgain()
    }

    private var photosSaveButton: some View {
        Button {
            saveToPhotos()
        } label: {
            switch photosSaveState {
            case .idle, .failed, .denied:
                Label("recap_save_to_photos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            case .saving:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .saved:
                Label("recap_saved_to_photos", systemImage: "checkmark.circle.fill")
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

    /// A film exported as a GIF before that format was removed (ADR file
    /// 2026-10-10). It still exists on disk and in the film list.
    private var isGIF: Bool {
        fileURL.pathExtension.lowercased() == "gif"
    }
}
