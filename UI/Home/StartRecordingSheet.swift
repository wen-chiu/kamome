import KamomeTrackingEngine
import SwiftUI

/// The step between Home's "Record a trip" button and a live recording: say
/// what recording does, pick the vehicle, start.
///
/// **The vehicle is asked here, not on Home** (Chiu 2026-09-23). On Home the
/// picker sat between the import and record buttons and read as if it applied
/// to both; it only ever mattered to recording, so it is asked once the user
/// has chosen to record — the same move PR #83 made for import, whose subject
/// is chosen at export.
struct StartRecordingSheet: View {
    @Binding var vehicle: VehicleType
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("record_sheet_body")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("vehicle_label", selection: $vehicle) {
                    Text("vehicle_car").tag(VehicleType.car)
                    Text("vehicle_scooter").tag(VehicleType.scooter)
                    Text("vehicle_bicycle").tag(VehicleType.bicycle)
                }
                .pickerStyle(.segmented)
                Spacer(minLength: 0)
                Button {
                    onStart()
                } label: {
                    Label("start_journey", systemImage: "location.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("live_capture_header")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("import_close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
