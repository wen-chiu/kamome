import KamomeConfig
import SwiftUI

/// What an empty 旅程 says: **足跡's welcome card, with 「找出我的旅程」** (Chiu
/// 2026-10-26, #290 option 1; ADR 2026-10-26-home-shows-a-newcomer-the-next-step).
/// Finding the journeys already in the photographs is the quickest way to see
/// what Kamome makes, and a newcomer only found it by opening the other
/// segment. Its button opens 足跡 and asks for the library there.
///
/// Import stays the manual route, at the foot of the screen; a sample film is
/// one quiet tap away for anyone who wants to see what Kamome makes first
/// (ADR 2026-09-28-sample-trip).
struct HomeEmptyState: View {
    let findJourneys: () -> Void
    let openSample: () throws -> Void
    @State private var sampleFailed = false

    var body: some View {
        VStack(spacing: 20) {
            WelcomeCard(isWorking: false, action: findJourneys)
            // A button, not a line of tinted text (2026-10-08): it is the
            // best first step for someone new, and read as a caption it was
            // easy to pass. Bordered, so the card's button stays the hero.
            Button {
                do {
                    try openSample()
                } catch {
                    KamomeLog.storage.error(
                        "sample trip could not be created: \(String(describing: error), privacy: .public)"
                    )
                    sampleFailed = true
                }
            } label: {
                Label("sample_open_action", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .alert("sample_failed", isPresented: $sampleFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 24)
    }
}
