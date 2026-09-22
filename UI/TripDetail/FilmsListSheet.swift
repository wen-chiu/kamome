import KamomeExportEngine
import KamomePersistence
import SwiftUI

/// All of a trip's exported films. Trip Detail shows only a one-line summary
/// of the latest one (Chiu 2026-09-22: the export list was permanently taking
/// up the page); this is where the rest live, reached by tapping that row —
/// skipped entirely when there is only one film, which opens straight to the
/// player instead.
struct FilmsListSheet: View {
    let films: [FilmRecord]
    let onSelect: (FilmRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(films) { film in
                Button {
                    onSelect(film)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: film.format == "gif" ? "photo.on.rectangle" : "film")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(film.format.uppercased())
                                .font(.subheadline.bold())
                            Text(Date(timeIntervalSince1970: film.createdAt), style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let bytes = film.fileBytes {
                            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .navigationTitle("films_section_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("recap_done") { dismiss() }
                }
            }
        }
    }
}
