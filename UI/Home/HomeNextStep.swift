import KamomePersistence
import SwiftUI

/// **What to do next, while 旅程 is short** (#295 item 1, ADR
/// 2026-10-26-home-shows-a-newcomer-the-next-step). Once the empty state goes,
/// one trip left most of the screen white and nothing said what to do next —
/// most often after the sample, which hides the empty state that offered
/// 「找出我的旅程」. So under a list of `home.next_step_max_trips` or fewer,
/// one line says the next step:
/// - a finished trip without a film: open it and make the film, the thing the
///   app is for;
/// - otherwise: find more journeys, which opens 足跡 as the empty state's
///   button does.
enum HomeNextStep: Equatable {
    case makeFilm
    case findJourneys

    /// Never with no trips (the empty state speaks), nor past the threshold,
    /// where the list fills the screen and says enough itself.
    static func isOffered(tripCount: Int, maxTrips: Int) -> Bool {
        tripCount > 0 && tripCount <= maxTrips
    }

    static func choose(finishedTripsWithoutFilm: Int) -> HomeNextStep {
        finishedTripsWithoutFilm > 0 ? .makeFilm : .findJourneys
    }

    /// One read per trip; called only for a list short enough to be offered a step.
    static func load(trips: [TripRecord], repository: TripRepository) -> HomeNextStep {
        let filmless = trips.filter { trip in
            trip.endedAt != nil && Stored.read("films") { try repository.films(tripId: trip.id) }?.isEmpty == true
        }
        return choose(finishedTripsWithoutFilm: filmless.count)
    }
}

/// The line under a short 旅程 list. Quiet: footnote type, centred, no card —
/// the list is the page, and this only points past its end.
struct HomeNextStepRow: View {
    let trips: [TripRecord]
    let repository: TripRepository
    let findJourneys: () -> Void

    /// Read when the row appears and whenever the trips change; a film made in
    /// Trip Detail is read on the way back, when the row appears again.
    @State private var step: HomeNextStep?

    var body: some View {
        Group {
            switch step {
            case .makeFilm:
                line("home_next_make_film", symbol: "film")
                    .foregroundStyle(.secondary)
            case .findJourneys:
                // Its glyph is 足跡's, the segment it opens.
                Button(action: findJourneys) {
                    line("home_next_find_journeys", symbol: "shoeprints.fill")
                        .fontWeight(.semibold)
                }
                // A default-style button in a List row takes the whole row's tap.
                .buttonStyle(.borderless)
            case nil:
                Color.clear.frame(height: 1)
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .task(id: trips) { step = HomeNextStep.load(trips: trips, repository: repository) }
    }

    /// The glyph and its words as one unit: a `Label` in a List row sets its
    /// icon in a column of its own, and the glyph drifted away from the line.
    private func line(_ key: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(key)
        }
    }
}
