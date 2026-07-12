import SwiftUI

/// §6 priming sheet: explains why Always location matters before iOS shows
/// its own dialog — background tracking happens only during an active trip.
struct AlwaysPrimingView: View {
    @Environment(TrackingSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("priming_title")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("priming_body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                session.grantAlwaysPermission()
                dismiss()
            } label: {
                Text("priming_allow")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            Button {
                dismiss()
            } label: {
                Text("priming_later")
                    .font(.subheadline)
            }
        }
        .padding(24)
    }
}
