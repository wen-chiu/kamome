import KamomeTrackingEngine
import SwiftUI

/// S1 Home / Trip List (minimal Phase 1 cut): trip list, vehicle selector,
/// big Start button. Cover thumbnails and stats arrive in Phase 2.
struct HomeView: View {
    @Environment(TrackingSession.self) private var session
    @State private var vehicle: VehicleType = .car

    var body: some View {
        NavigationStack {
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
        List(session.trips, id: \.id) { trip in
            VStack(alignment: .leading) {
                Text(trip.title)
                    .font(.headline)
                Text(Date(timeIntervalSince1970: trip.startedAt), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
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
