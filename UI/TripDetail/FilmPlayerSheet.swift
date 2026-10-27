import AVKit
import KamomePersistence
import SwiftUI

/// Full-screen player for a stored film, opened from the trip detail's films
/// section. Plays immediately.
///
/// **The same pair as the finished screen** (Chiu 2026-10-26, #295 item 9):
/// Save to Photos and Share under the film, Delete in ⋯ and still asked first.
/// A red Delete used to sit beside Share with Save missing, so the action
/// someone opening a film most likely wants was not there, and the one that
/// cannot be undone carried the same weight as Share.
struct FilmPlayerSheet: View {
    let film: FilmRecord
    let onDelete: () -> Void

    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private var fileDetail: String {
        var parts = [film.format.uppercased()]
        parts.append(DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: film.createdAt), dateStyle: .medium, timeStyle: .none
        ))
        if let bytes = film.fileBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }

                if let url = FilmStore.resolvedURL(relativePath: film.relativePath) {
                    FilmSaveShareActions(fileURL: url)
                        .padding(.horizontal)
                        .padding(.bottom)
                }

                // Format, date and size used to sit on Trip Detail's films row;
                // they belong with the film, not on every visit to the trip
                // (Chiu 2026-09-23).
                Text(fileDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                // The render-budget readout is a developer's number: Debug only
                // (Chiu 2026-10-10, #288, reopening 2026-09-26).
                #if DEBUG
                if let renderSeconds = film.renderSeconds {
                    Text(String.localizedStringWithFormat(
                        String(localized: "recap_render_time"),
                        String(format: "%.1f", renderSeconds)
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                }
                #endif
            }
            .navigationTitle("recap_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 「關閉」, as on the export sheet (#291): nothing here is
                    // being finished.
                    Button("recap_close") { dismiss() }
                }
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
                    onDelete()
                }
            }
        }
        .onAppear {
            guard let url = FilmStore.resolvedURL(relativePath: film.relativePath) else { return }
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
