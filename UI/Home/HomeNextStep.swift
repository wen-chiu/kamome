import KamomePersistence
import SwiftUI

/// **What to do next, while 旅程 is short** (#295 item 1, ADR
/// 2026-10-26-home-shows-a-newcomer-the-next-step). Once the empty state goes,
/// one trip left most of the screen white and nothing said what to do next —
/// most often after the sample, which hides the empty state that offered
/// 「找出我的旅程」. So under a list of `home.next_step_max_trips` or fewer,
/// a card you can press (Chiu 2026-10-27: a card that does, not a line that
/// explains):
/// - the newest finished trip without a film: make its film, the thing the
///   app is for, straight to that trip's film sheet;
/// - otherwise: find more journeys, as the empty state's button does.
enum HomeNextStep: Equatable {
    case makeFilm(TripRecord)
    case findJourneys

    /// Never with no trips (the empty state speaks), nor past the threshold,
    /// where the list fills the screen and says enough itself.
    static func isOffered(tripCount: Int, maxTrips: Int) -> Bool {
        tripCount > 0 && tripCount <= maxTrips
    }

    /// The trip to make a film of: of the finished trips without one, the one
    /// that began last. A trip still recording has no film to make yet.
    static func tripToFilm(_ trips: [TripRecord], hasFilm: (TripRecord) -> Bool) -> TripRecord? {
        trips.filter { $0.endedAt != nil && !hasFilm($0) }.max { $0.startedAt < $1.startedAt }
    }

    /// One read per trip; called only for a list short enough to be offered a
    /// step. A trip whose films cannot be read is not offered for a film.
    static func load(trips: [TripRecord], repository: TripRepository) -> HomeNextStep {
        let trip = tripToFilm(trips) { trip in
            Stored.read("films") { try repository.films(tripId: trip.id) }?.isEmpty != true
        }
        return trip.map(HomeNextStep.makeFilm) ?? .findJourneys
    }
}

/// The card under a short 旅程 list. Both cards' buttons are bordered: import,
/// at the foot of the screen, stays its one filled button (§7 rule ①).
struct HomeNextStepRow: View {
    let trips: [TripRecord]
    let repository: TripRepository
    /// Opens a trip with its film sheet (`HomeRoute.tripMakingFilm`).
    let makeFilm: (String) -> Void
    let findJourneys: () -> Void

    /// Read when the row appears and whenever the trips change; a film made in
    /// Trip Detail is read on the way back, when the row appears again.
    @State private var step: HomeNextStep?

    var body: some View {
        Group {
            switch step {
            case let .makeFilm(trip):
                NextStepCard(showsGull: false, text: Text(verbatim: Self.filmCardText(for: trip))) {
                    Button { makeFilm(trip.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "film")
                            Text("make_film")
                        }
                    }
                }
            case .findJourneys:
                NextStepCard(showsGull: true, text: Text("home_next_find_title")) {
                    // Its glyph is 足跡's, the segment it opens.
                    Button(action: findJourneys) {
                        HStack(spacing: 6) {
                            Image(systemName: "shoeprints.fill")
                            Text("home_next_find_action")
                        }
                    }
                }
            case nil:
                Color.clear.frame(height: 1)
            }
        }
        .padding(.top, 16)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .task(id: trips) { step = HomeNextStep.load(trips: trips, repository: repository) }
    }

    /// 「把「🇹🇼 花蓮」做成旅程影片」: the trip by the name its row shows
    /// (`HomeTripRow.headline`, the trip title rule), flag included.
    static func filmCardText(for trip: TripRecord) -> String {
        let headline = HomeTripRow.headline(for: trip)
        let name = headline.flag.map { "\($0) \(headline.title)" } ?? headline.title
        return String.localizedStringWithFormat(String(localized: "home_next_film_card"), name)
    }
}

/// 足跡's welcome card, compact: an optional gull, one line, one bordered
/// button. **On white, not the welcome card's grey**: a bordered label on
/// `#F2F2F7` is 4.21 : 1 (ADR 2026-10-26-text-and-controls-take-a-deeper-teal),
/// so in light mode the card is white with a hairline edge; in dark it is the
/// welcome card's `#1C1C1E`.
private struct NextStepCard<Action: View>: View {
    let showsGull: Bool
    let text: Text
    @ViewBuilder let action: Action

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsGull { KamomeGull(size: 40) }
            text
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            action
                // Glyph and word in an HStack, not a `Label`: in a List row a
                // label sets its glyph in a column of its own, apart from the word.
                .font(.subheadline.weight(.semibold))
                // In a List row a default-style button takes the whole row's tap.
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}
