import KamomeConfig
import Photos
import SwiftUI

/// **Save and Share, the pair under a film** — on the finished screen and in
/// the film player, so a film reads the same wherever it is opened (Chiu
/// 2026-10-26, #295 item 9). Moved here whole from `RecapFinishedView` when the
/// player became its second user; the behaviour did not change.
///
/// The pair is one row of one height, and a denied or failed save is a sentence
/// under it, never inside the button (ADR 2026-10-02-the-finished-screen-is-the-film).
struct FilmSaveShareActions: View {
    let fileURL: URL
    @State private var photosSaveState: PhotosSaveState = .idle

    enum PhotosSaveState: Equatable {
        case idle
        case saving
        case saved
        case denied
        /// The reason is logged, never shown — `PHPhotosErrorDomain 3302` is
        /// not a sentence (DESIGNER.md UX rule 5).
        case failed
    }

    var body: some View {
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
        }
    }

    private var saveNote: LocalizedStringKey? {
        switch photosSaveState {
        case .failed: return "recap_save_failed"
        case .denied: return "recap_photos_access_denied"
        case .idle, .saving, .saved: return nil
        }
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
        .buttonStyle(.prominent)
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
        // A film exported as a GIF before that format was removed (ADR file
        // 2026-10-10) still exists on disk and in the film list.
        let savesAsPhoto = fileURL.pathExtension.lowercased() == "gif"
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
}
