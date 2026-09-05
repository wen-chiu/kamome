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
/// **Two sentences and a pointer, and that is the whole card** (Chiu
/// 2026-09-06). It was the full privacy notice first; a wall of text at first
/// launch is not read, and a notice nobody reads discloses nothing. The detail
/// it dropped — the payload, retention, the control, what the relay is — is on
/// `AboutView`, which is where someone goes when they want it, and the last line
/// says so.
///
/// **Every sentence is still `AboutView`'s sentence** (`PrivacyNoticeCopy`):
/// the card shows the lead, `AboutView` shows the lead *and* the rest. Nothing
/// is written twice, so the two cannot drift.
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
