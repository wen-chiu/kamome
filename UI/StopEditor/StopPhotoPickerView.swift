import KamomePersistence
import SwiftUI

/// Every photograph at one stop, and which of them the film shows (ADR
/// 2026-09-24, reworked by Chiu 2026-09-25).
///
/// **What is numbered is what plays.** The numbers are the stop's deck, read
/// from the same plan the export composes. A tap on a numbered photograph takes
/// it out; a tap on any other puts it in — 1 to `maxPhotos`. The first tap turns
/// the app's choice into the person's, and "Automatic" hands it back. Press and
/// hold leaves a photograph out of anything the app picks. A star is a Photos
/// favourite: the app picks those first, and it is shown, not set, here.
struct StopPhotoPickerView: View {
    let choices: FilmPhotoChoices
    let stop: StopRecord

    @State private var confirmingTakeOut = false
    @State private var fullNotice = 0

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 4)]

    var body: some View {
        let photos = choices.photos(for: stop.id)
        let deck = choices.filmDeck(for: stop.id)
        let inFilm = choices.isInFilm(stopId: stop.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(deck: deck, total: photos.count, inFilm: inFilm)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(photos, id: \.id) { photo in
                        tile(photo, filmPosition: deck.firstIndex(of: photo.phAssetId))
                    }
                }
                .padding(.horizontal, 4)
                Text(String.localizedStringWithFormat(String(localized: "stop_photos_hint"), choices.maxPhotos))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle(stop.name ?? String(localized: "stop_unnamed"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if choices.isPicked(stopId: stop.id) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("stop_photos_reset") { choices.resetToAuto(stopId: stop.id) }
                }
            }
        }
        .sensoryFeedback(.warning, trigger: fullNotice)
        .confirmationDialog("stop_photos_last_title", isPresented: $confirmingTakeOut, titleVisibility: .visible) {
            Button("stop_take_out", role: .destructive) {
                choices.takeOut(stopId: stop.id, clearPicks: true)
            }
        } message: {
            Text("stop_photos_last_message")
        }
    }

    /// Whether the stop is in the film, how many photographs it shows, and who
    /// chose them.
    private func header(deck: [String], total: Int, inFilm: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { inFilm },
                set: { $0 ? choices.putIn(stopId: stop.id) : choices.takeOut(stopId: stop.id) }
            )) {
                Label("stop_in_film_toggle", systemImage: "film")
                    .font(.subheadline.weight(.medium))
            }
            if inFilm {
                HStack(spacing: 6) {
                    Text(String.localizedStringWithFormat(
                        String(localized: "stop_photos_in_film"), deck.count, total
                    ))
                    Text(choices.isPicked(stopId: stop.id) ? "stop_photos_mode_picked" : "stop_photos_mode_auto")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text("stop_photos_not_in_film")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if fullNotice > 0 {
                Text(String.localizedStringWithFormat(String(localized: "stop_photos_full"), choices.maxPhotos))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func tap(_ photo: PhotoRefRecord) {
        switch choices.toggle(photo, stopId: stop.id) {
        case .changed: fullNotice = 0
        case .full: fullNotice += 1
        case .wouldEmptyStop: confirmingTakeOut = true
        }
    }

    private func tile(_ photo: PhotoRefRecord, filmPosition: Int?) -> some View {
        let excluded = photo.isExcluded != 0
        return Button {
            tap(photo)
        } label: {
            // A square cell the thumbnail fills: `Color.clear` fixes the shape,
            // the photo is cropped into it rather than sizing it.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    PhotoThumbnail(assetId: photo.phAssetId, targetPx: 240)
                        .opacity(excluded ? 0.35 : 1)
                }
                .overlay { badges(photo: photo, filmPosition: filmPosition) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if filmPosition != nil {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if excluded {
                Button("stop_photos_include", systemImage: "eye") { choices.setChoice(.auto, photo: photo) }
            } else {
                Button("stop_photos_exclude", systemImage: "eye.slash") { choices.setChoice(.excluded, photo: photo) }
            }
        }
        .accessibilityLabel(Text(accessibilityState(photo: photo, filmPosition: filmPosition)))
        .accessibilityHint(Text("stop_photos_tile_hint"))
    }

    private func badges(photo: PhotoRefRecord, filmPosition: Int?) -> some View {
        VStack {
            HStack {
                if let filmPosition {
                    Text("\(filmPosition + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(Color.accentColor))
                } else {
                    // An empty ring says "tap to add", as in a multi-select.
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .background(Circle().fill(.black.opacity(0.2)))
                        .frame(width: 20, height: 20)
                        .shadow(radius: 1)
                }
                Spacer()
                if photo.isHighlight != 0 {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 1)
                }
            }
            Spacer()
            if photo.isExcluded != 0 {
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

    private func accessibilityState(photo: PhotoRefRecord, filmPosition: Int?) -> String {
        var parts: [String] = []
        if let filmPosition {
            parts.append(String.localizedStringWithFormat(String(localized: "stop_photos_a11y_in_film"), filmPosition + 1))
        } else {
            parts.append(String(localized: "stop_photos_a11y_not_in_film"))
        }
        if photo.isHighlight != 0 { parts.append(String(localized: "stop_photos_a11y_starred")) }
        if photo.isExcluded != 0 { parts.append(String(localized: "stop_photos_a11y_excluded")) }
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
                if choices.isPicked(stopId: stop.id) {
                    Image(systemName: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("stop_photos_mode_picked"))
                }
                if choices.photos(for: stop.id).isEmpty {
                    // A pin in the film: a count of "0 / 0" would read as broken.
                    Text("recap_stop_no_photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if choices.isInFilm(stopId: stop.id) {
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
