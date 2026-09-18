import KamomeTrackingEngine
import SwiftUI

/// Live capture's entry, moved off the home screen into a sheet (2026-09-17).
/// Recording is secondary to discovery and graduates to Capture Beta (Phase 5);
/// the vehicle picker and the Start button are unchanged, only where they live.
struct StartRecordingSheet: View {
    let session: TrackingSession
    @State private var vehicle: VehicleType = .car
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("live_capture_body")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Picker("vehicle_label", selection: $vehicle) {
                    Text("vehicle_car").tag(VehicleType.car)
                    Text("vehicle_scooter").tag(VehicleType.scooter)
                    Text("vehicle_bicycle").tag(VehicleType.bicycle)
                }
                .pickerStyle(.segmented)
                Button {
                    dismiss()
                    session.start(vehicle: vehicle)
                } label: {
                    Text("start_journey")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(24)
            .navigationTitle("live_capture_header")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("import_close") { dismiss() }
                }
            }
        }
    }
}
