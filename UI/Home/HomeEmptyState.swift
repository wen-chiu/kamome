import KamomeConfig
import SwiftUI

/// What an empty Home says: import is the way in, and a sample film is one
/// quiet tap away for anyone who wants to see what Kamome makes first
/// (ADR 2026-09-28-sample-trip). Import stays the hero, below.
struct HomeEmptyState: View {
    let openSample: () throws -> Void
    @State private var sampleFailed = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("empty_state_pitch")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("empty_state_import_hint")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // A button, not a line of tinted text (2026-10-08): it is the
            // best first step for someone new, and read as a caption it was
            // easy to pass. Bordered, so the import below stays the hero.
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
            .padding(.top, 8)
            .alert("sample_failed", isPresented: $sampleFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 24)
    }
}
