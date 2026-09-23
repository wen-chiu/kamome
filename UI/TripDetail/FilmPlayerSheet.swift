import AVKit
import KamomePersistence
import SwiftUI

/// Full-screen player for a stored film, opened from the trip detail's films
/// section. Plays immediately; offers share and delete.
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

                HStack(spacing: 16) {
                    if let url = FilmStore.resolvedURL(relativePath: film.relativePath) {
                        ShareLink(item: url) {
                            Label("recap_share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("recap_film_delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
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
                .padding(.horizontal)
                .padding(.bottom)

                // Format, date and size used to sit on Trip Detail's films row;
                // they belong with the film, not on every visit to the trip
                // (Chiu 2026-09-23).
                Text(fileDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                if let renderSeconds = film.renderSeconds {
                    Text(String.localizedStringWithFormat(
                        String(localized: "recap_render_time"),
                        String(format: "%.1f", renderSeconds)
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("recap_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("recap_done") { dismiss() }
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
