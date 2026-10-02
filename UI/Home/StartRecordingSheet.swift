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
///
/// **With location refused there is nothing to start** (Chiu 2026-10-02, #190),
/// so the sheet says what recording needs and where to allow it, in place of
/// the picker and the button. It stays up while the system prompt is answered:
/// a yes starts the recording and Home closes the sheet, a no turns it into
/// that message.
struct StartRecordingSheet: View {
    @Binding var vehicle: VehicleType
    let access: LocationAccess
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if access == .refused {
                    locationRefused
                } else {
                    startForm
                }
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

    private var startForm: some View {
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
    }

    /// Scrolls, so the way to Settings is reachable at any text size.
    private var locationRefused: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "location.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("record_location_refused_title")
                    .font(.title3.weight(.semibold))
                Text("record_location_refused_body")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settings) {
                        Text("access_denied_settings")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
