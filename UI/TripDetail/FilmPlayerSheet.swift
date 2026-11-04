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
///
/// **「換音樂」** (handoff-music §4.2) sits under the actions: a choice is
/// rendered beside the picture and played here before 「使用這首」 keeps it.
struct FilmPlayerSheet: View {
    let onDelete: () -> Void
    /// The film's row changed (its music): the screen behind reloads.
    var onChange: (FilmRecord) -> Void = { _ in }

    @State private var editor: FilmMusicEditor
    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(film: FilmRecord, session: TrackingSession, onDelete: @escaping () -> Void,
         onChange: @escaping (FilmRecord) -> Void = { _ in }) {
        self.onDelete = onDelete
        self.onChange = onChange
        _editor = State(initialValue: FilmMusicEditor(
            film: film, config: session.config, repository: session.repository
        ))
    }

    private var film: FilmRecord { editor.film }

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
                        // Saving or sharing the preview's music would be a
                        // choice the person has not made yet.
                        .disabled(editor.trial != nil)
                }

                FilmMusicControl(editor: editor) { onChange($0) }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

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
            FilmAudioSession.preparePlayback()
            play()
        }
        .onChange(of: editor.revision) { play() }
        .onDisappear {
            player?.pause()
            player = nil
            // Closing throws a preview nobody kept away (§4.2).
            editor.discard()
        }
    }

    private func play() {
        player?.pause()
        guard let url = editor.playbackURL else { return }
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
    }
}
