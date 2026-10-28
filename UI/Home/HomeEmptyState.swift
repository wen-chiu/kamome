import KamomeConfig
import SwiftUI

/// What an empty 旅程 says: **足跡's welcome card, with 「找出我的旅程」** (Chiu
/// 2026-10-26, #290 option 1; ADR 2026-10-26-home-shows-a-newcomer-the-next-step).
/// Finding the journeys already in the photographs is the quickest way to see
/// what Kamome makes, and a newcomer only found it by opening the other
/// segment. Its button opens 足跡 and asks for the library there.
///
/// The screen reads in three levels (Chiu 2026-10-27): 「找出我的旅程」, the
/// one filled button; then a sample film, one quiet tap away for anyone who
/// wants to see what Kamome makes first (ADR 2026-09-28-sample-trip); then
/// the manual route, import and record, small and side by side.
struct HomeEmptyState: View {
    let findJourneys: () -> Void
    let openSample: () throws -> Void
    let importTrip: () -> Void
    let recordTrip: () -> Void
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
            manualRoute
                .padding(.top, 8)
        }
        // Its own height, always: offered the room's height, the stack
        // squeezed the welcome card's body to one line ending in "…".
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 24)
    }

    /// Import and record, the two ways in that do not need Kamome to look:
    /// one row of small bordered buttons, stacked when a large text size
    /// leaves no room for both on one line. The same glyphs as the full-width
    /// pair a trip list has at its foot.
    private var manualRoute: some View {
        VStack(spacing: 10) {
            Text("home_manual_title")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { manualButtons }
                VStack(spacing: 10) { manualButtons }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var manualButtons: some View {
        Button(action: importTrip) {
            Label("home_manual_import", systemImage: "photo.stack")
        }
        Button(action: recordTrip) {
            Label("home_manual_record", systemImage: "location.fill")
        }
    }
}
