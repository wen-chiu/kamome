import SwiftUI

// Beside `TripDetailView` rather than in it, for SwiftLint's type-body limit.
extension TripDetailView {
    /// **The app's core action, named and at the foot of the screen** (Chiu
    /// 2026-10-10, #285). It was an unlabelled film-strip icon beside the edit
    /// pencil, and on a first walk the person could not find how to make the
    /// film the app exists to make. Same weight as Home's import button, the
    /// list scrolling under it the same way.
    var makeFilmButton: some View {
        FilmButtonBar(canMakeFilm: canMakeFilm, onePlace: model.saysFilmHasOnePlace) {
            showingRecap = true
        }
    }

    /// The model's rule (`TripDetailModel.canMakeFilm`), read where the view
    /// acts on it.
    var canMakeFilm: Bool { model.canMakeFilm }

    /// **Home's 「製作旅程影片」 opens this trip's film sheet** (Chiu 2026-10-27,
    /// ADR 2026-10-26-home-shows-a-newcomer-the-next-step). The same sheet as
    /// the button below, opened once, as soon as the button could be pressed:
    /// one film at a time stays `RecapExportCoordinator`'s, as from here.
    func openPendingFilmSheet() {
        guard filmSheetPending, canMakeFilm else { return }
        filmSheetPending = false
        showingRecap = true
    }
}

/// The bar at the foot of Trip Detail: the film button, and — for a trip of
/// one place — the one sentence that says why it is disabled (Chiu 2026-11-04,
/// ADR 2026-11-04-a-trip-of-one-place-is-refused-before-the-film-button).
///
/// **VoiceOver hears the reason either way it arrives**: the sentence is
/// ordinary text, read before the button, and the button carries it as its
/// hint, so landing on the button straight from the rotor or by touch still
/// says why it is dimmed. With hints off, the text alone still says it.
struct FilmButtonBar: View {
    let canMakeFilm: Bool
    let onePlace: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if onePlace {
                Text("make_film_one_place")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: action) {
                Label("make_film", systemImage: "film")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.prominent)
            .disabled(!canMakeFilm)
            .accessibilityHint(onePlace ? Text("make_film_one_place") : Text(verbatim: ""))
        }
        // As large as Home's two at the first accessibility size, no larger:
        // past that they took the screen from the list (#205).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }
}
