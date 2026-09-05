import KamomeConfig
import SwiftUI

/// **The first-run notice** — shown once, before this build can send a real
/// coordinate anywhere, then remembered (Chiu 2026-09-04; ADR 2026-09-05).
///
/// It **informs and is acknowledged; it does not ask.** There is one button and
/// it says "Got it": no accept, no decline, no toggle. A refusal would have to
/// switch route matching off and be reversible somewhere in the app, and neither
/// exists — offering the choice without the mechanism is the dishonest half of a
/// question. That omission is **deliberately deferred**, in the ADR, rather than
/// half-built here.
///
/// **Every sentence is `AboutView`'s sentence** (`PrivacyNoticeCopy`), in the
/// same order, so the one-time telling and the screen a user can go back to
/// cannot say different things. ⏳ The wording is still Chiu's and is not ruled
/// on (`Docs/release-readiness.md` S2/S3); this ships so the obligation is met
/// rather than deferred.
struct FirstRunNoticeView: View {
    let matching: TrackingConfig.Matching
    /// Supplied by the presenter, so this view stores nothing and the fact
    /// "the user was told" is written in exactly one place.
    let acknowledge: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("privacy_intro")
                    // The load-bearing sentence: which parties handle a
                    // journey's coordinates on the way to the roads.
                    Text(LocalizedStringKey(PrivacyNoticeCopy.hopKey(for: matching)))
                    Text(PrivacyNoticeCopy.importedBody(for: matching))
                    Text("privacy_retention")
                    Text("privacy_control")
                    Text("first_run_where")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("privacy_header")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: acknowledge) {
                    Text("first_run_acknowledge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        // The button is the only way out, so that the remembered fact is "the
        // user was told and closed it" rather than "a sheet went away".
        .interactiveDismissDisabled()
    }
}
