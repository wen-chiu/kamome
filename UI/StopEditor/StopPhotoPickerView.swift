import KamomePersistence
import SwiftUI

/// Every photograph at one stop, and what the film does with each (ADR
/// 2026-09-24). Replaces the Stop Editor's 72 pt strip, where a tap marked a
/// highlight that — for a photo-dense stop — usually never reached the film.
///
/// Three states, one gesture each: **tap** stars a photo (it always goes in, up
/// to `deck_highlight_max_photos`), **press and hold** leaves one out (it never
/// does), and anything untouched is the app's to choose. A number on a tile is
/// its place in this stop's deck, read from the same plan the export composes —
/// so what this screen promises is what the film shows.
struct StopPhotoPickerView: View {
    let choices: FilmPhotoChoices
    let stop: StopRecord

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 4)]

    var body: some View {
        let photos = choices.photos(for: stop.id)
        let deck = choices.filmDeck(for: stop.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summary(deck: deck, total: photos.count)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(photos, id: \.id) { photo in
                        tile(photo, filmPosition: deck.firstIndex(of: photo.phAssetId))
                    }
                }
                .padding(.horizontal, 4)
                Text(String.localizedStringWithFormat(
                    String(localized: "stop_photos_hint"), choices.highlightMaxPhotos
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(stop.name ?? String(localized: "stop_unnamed"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "3 of 48 photos are in the film", or why this stop is not in it at all.
    @ViewBuilder
    private func summary(deck: [String], total: Int) -> some View {
        if choices.isInFilm(stopId: stop.id) {
            Label(
                String.localizedStringWithFormat(String(localized: "stop_photos_in_film"), deck.count, total),
                systemImage: "film"
            )
            .font(.subheadline.weight(.medium))
        } else {
            Label("stop_photos_not_in_film", systemImage: "film.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func tile(_ photo: PhotoRefRecord, filmPosition: Int?) -> some View {
        let choice = photo.filmChoice
        return Button {
            choices.setChoice(choice == .starred ? .auto : .starred, photo: photo)
        } label: {
            // A square cell the thumbnail fills: `Color.clear` fixes the shape,
            // the photo is cropped into it rather than sizing it.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    PhotoThumbnail(assetId: photo.phAssetId, targetPx: 240)
                        .opacity(choice == .excluded ? 0.35 : 1)
                }
                .overlay { badges(choice: choice, filmPosition: filmPosition) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if filmPosition != nil {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if choice == .excluded {
                Button("stop_photos_include", systemImage: "eye") { choices.setChoice(.auto, photo: photo) }
            } else {
                Button("stop_photos_exclude", systemImage: "eye.slash") { choices.setChoice(.excluded, photo: photo) }
            }
        }
        .accessibilityLabel(Text(accessibilityState(choice: choice, filmPosition: filmPosition)))
        .accessibilityHint(Text("stop_photos_tile_hint"))
    }

    private func badges(choice: PhotoRefRecord.FilmChoice, filmPosition: Int?) -> some View {
        VStack {
            HStack {
                if let filmPosition {
                    Text("\(filmPosition + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(Color.accentColor))
                }
                Spacer()
                if choice == .starred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 1)
                }
            }
            Spacer()
            if choice == .excluded {
                HStack {
                    Spacer()
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
            }
        }
        .padding(5)
    }

    private func accessibilityState(choice: PhotoRefRecord.FilmChoice, filmPosition: Int?) -> String {
        var parts: [String] = []
        if let filmPosition {
            parts.append(String.localizedStringWithFormat(String(localized: "stop_photos_a11y_in_film"), filmPosition + 1))
        }
        switch choice {
        case .starred: parts.append(String(localized: "stop_photos_a11y_starred"))
        case .excluded: parts.append(String(localized: "stop_photos_a11y_excluded"))
        case .auto: break
        }
        if parts.isEmpty { parts.append(String(localized: "stop_photos_a11y_not_in_film")) }
        return parts.joined(separator: ", ")
    }
}

/// One stop's line in a list of what the film shows: its name, how many of its
/// photographs are in, and those photographs in deck order. The Stop Editor and
/// the export sheet both open the picker from it.
struct FilmDeckRow: View {
    let choices: FilmPhotoChoices
    let stop: StopRecord
    var showsName = true

    var body: some View {
        let deck = choices.filmDeck(for: stop.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if showsName {
                    Text(stop.name ?? String(localized: "stop_unnamed")).lineLimit(1)
                } else {
                    Text("stop_photos_row")
                }
                Spacer()
                if choices.isInFilm(stopId: stop.id) {
                    Text(verbatim: "\(deck.count) / \(choices.photos(for: stop.id).count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "film.slash").foregroundStyle(.secondary)
                }
            }
            if !deck.isEmpty {
                HStack(spacing: 4) {
                    ForEach(deck, id: \.self) { assetId in
                        PhotoThumbnail(assetId: assetId)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}
