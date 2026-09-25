import KamomePersistence
import SwiftUI

/// The export sheet's say over which stops the film presents and what each
/// shows (ADR 2026-09-24, Chiu 2026-09-25). The app has already chosen; this is
/// where someone corrects it before a frame is rendered.
///
/// Two lists over the same trip. **In the film**: each row opens that stop's
/// photographs; swipe to take a stop out, and nothing takes its place. **Other
/// stops**: the ones the app left out and the ones the person took out, each
/// one tap from going in — the film grows to fit.
struct FilmStopsSections: View {
    let choices: FilmPhotoChoices

    var body: some View {
        let inFilm = choices.filmStops
        Section {
            ForEach(inFilm, id: \.id) { stop in
                NavigationLink {
                    StopPhotoPickerView(choices: choices, stop: stop)
                } label: {
                    FilmDeckRow(choices: choices, stop: stop)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        withAnimation { choices.takeOut(stopId: stop.id) }
                    } label: {
                        Label("stop_take_out", systemImage: "minus.circle")
                    }
                    .tint(.orange)
                }
            }
        } header: {
            Text(String.localizedStringWithFormat(String(localized: "recap_stops_in_film"), inFilm.count))
        } footer: {
            Text("recap_stops_in_film_footer")
        }

        let others = choices.otherStops
        if !others.isEmpty {
            Section {
                ForEach(others, id: \.id) { stop in
                    NavigationLink {
                        StopPhotoPickerView(choices: choices, stop: stop)
                    } label: {
                        otherRow(stop)
                    }
                }
            } header: {
                Text("recap_stops_other")
            } footer: {
                Text("recap_stops_other_footer")
            }
        }
    }

    /// A stop the film does not present: its name, how many photographs it has,
    /// a glimpse of them, and the button that puts it in.
    private func otherRow(_ stop: StopRecord) -> some View {
        let photos = choices.usablePhotos(for: stop.id)
        return HStack(spacing: 12) {
            Button {
                withAnimation { choices.putIn(stopId: stop.id) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            // Borderless, so the button takes its own tap inside a row that
            // otherwise opens the picker.
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("stop_put_in"))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stop.name ?? String(localized: "stop_unnamed")).lineLimit(1)
                    Spacer()
                    if choices.isTakenOut(stopId: stop.id) {
                        Text("recap_stop_taken_out")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !photos.isEmpty {
                        Text(String.localizedStringWithFormat(String(localized: "recap_stop_photo_count"), photos.count))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if !photos.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(glimpse(photos), id: \.id) { photo in
                            PhotoThumbnail(assetId: photo.phAssetId)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .opacity(0.6)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// A few photographs from across the visit, so a stop is recognisable
    /// before it is opened. Presentation only — never what the film would pick.
    private func glimpse(_ photos: [PhotoRefRecord]) -> [PhotoRefRecord] {
        let count = min(photos.count, 4)
        return (0..<count).map { photos[($0 * 2 + 1) * photos.count / (count * 2)] }
    }
}
