import SwiftUI

/// **Export waits for a stop that is still being named** (#160, ADR 2026-10-01).
///
/// Trip Detail opens the export sheet once the stops the app chose are named;
/// the rest of the trip is still being named behind it. A stop put into the
/// film from that rest would be filmed as "Unnamed stop", so Export is off
/// until it has its name, it is named next, and this line says why — in the
/// words Trip Detail's banner uses.
struct FilmNamingNote: View {
    let tripId: String
    let stopIds: Set<String>

    var body: some View {
        if StopNamingCoordinator.shared.isNaming(tripId, anyOf: stopIds),
           let naming = StopNamingCoordinator.shared.progress[tripId] {
            Text(String.localizedStringWithFormat(
                String(localized: "naming_stops_progress"), naming.completed, naming.total
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    /// Off while any of `stopIds` is owed a name; those stops go to the front
    /// of the naming queue whenever the set changes.
    func waitsForNaming(tripId: String, of stopIds: Set<String>) -> some View {
        disabled(StopNamingCoordinator.shared.isNaming(tripId, anyOf: stopIds))
            .onChange(of: stopIds) { StopNamingCoordinator.shared.nameFirst(stopIds, tripId: tripId) }
    }
}
