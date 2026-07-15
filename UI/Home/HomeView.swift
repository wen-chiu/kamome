import KamomeTrackingEngine
import KamomeTripComposer
import SwiftUI

/// S1 Home / Trip List: trip cards (title, date, distance, stops), vehicle
/// selector, big Start button. Cover map thumbnails remain a later polish.
struct HomeView: View {
    @Environment(TrackingSession.self) private var session
    @State private var vehicle: VehicleType = .car
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                if session.trips.isEmpty {
                    emptyState
                } else {
                    tripList
                }
                Spacer()
                vehiclePicker
                startButton
            }
            .padding()
            .navigationTitle(Text("home_title"))
            .fullScreenCover(isPresented: .constant(session.isRecording)) {
                RecordingView()
            }
        }
        .preferredColorScheme(.dark) // dark-mode-first: maps look better (§5)
        .onAppear {
            #if DEBUG
            // Demo screenshot automation (Phase 2 gate): jump straight to S3.
            if ProcessInfo.processInfo.arguments.contains("-demo-open-trip"),
               let first = session.trips.first {
                path = [first.id]
            }
            #endif
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bird")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("empty_state_pitch")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var tripList: some View {
        List(session.trips) { trip in
            NavigationLink(value: trip.id) {
                VStack(alignment: .leading) {
                    Text(trip.title)
                        .font(.headline)
                    HStack {
                        Text(Date(timeIntervalSince1970: trip.startedAt), style: .date)
                        if let stats = TripStats.from(jsonString: trip.statsJson) {
                            Text(String(format: "· %.0f km · %d", stats.distanceM / 1000, stats.stopCount))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { tripId in
            TripDetailView(tripId: tripId, session: session)
        }
    }

    private var vehiclePicker: some View {
        Picker("vehicle_label", selection: $vehicle) {
            Text("vehicle_car").tag(VehicleType.car)
            Text("vehicle_scooter").tag(VehicleType.scooter)
            Text("vehicle_bicycle").tag(VehicleType.bicycle)
        }
        .pickerStyle(.segmented)
    }

    private var startButton: some View {
        Button {
            session.start(vehicle: vehicle)
        } label: {
            Text("start_journey")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }
}
