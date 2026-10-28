import SwiftUI

// Beside `TripDetailView` rather than in it, for SwiftLint's type-body limit.
extension TripDetailView {
    /// **The app's core action, named and at the foot of the screen** (Chiu
    /// 2026-10-10, #285). It was an unlabelled film-strip icon beside the edit
    /// pencil, and on a first walk the person could not find how to make the
    /// film the app exists to make. Same weight as Home's import button, the
    /// list scrolling under it the same way.
    var makeFilmButton: some View {
        Button {
            showingRecap = true
        } label: {
            Label("make_film", systemImage: "film")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.prominent)
        .disabled(!canMakeFilm)
        // As large as Home's two at the first accessibility size, no larger:
        // past that they took the screen from the list (#205).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// S5 entry: only completed trips have a recap to render. Naming is
    /// throttled and asynchronous; a film exported before its stops are named
    /// says "Unnamed stop" for each of them (Chiu 2026-08-04). It waits only
    /// for the stops a film shows (#160); the banner above keeps counting the
    /// rest. The button and Home's path to the sheet both wait on this.
    var canMakeFilm: Bool {
        model.detail?.trip.endedAt != nil && !model.isNamingFilmStops
    }

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
