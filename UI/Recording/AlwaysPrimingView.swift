import SwiftUI

/// §6 priming sheet: explains why Always location matters before iOS shows
/// its own dialog — background tracking happens only during an active trip.
struct AlwaysPrimingView: View {
    @Environment(TrackingSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The words scroll and the two answers stay put, as on the record
        // sheet (#191): at the largest text sizes the title and the body were
        // each cut to one line with an ellipsis.
        ScrollView {
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
            }
            .frame(maxWidth: .infinity)
            .padding([.horizontal, .top], 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
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
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
            // Only where the words can scroll under "Not Now": at ordinary
            // sizes everything fits and the sheet keeps its own material.
            .background(dynamicTypeSize.isAccessibilitySize ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
    }
}
