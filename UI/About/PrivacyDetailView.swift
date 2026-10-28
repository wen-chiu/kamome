import KamomeConfig
import SwiftUI

/// 「詳細說明」: the technical half of the privacy notice, one row below its
/// plain half on `AboutView` (Chiu 2026-10-26, #293). Nothing here was cut or
/// reworded to move it; the payloads, the tiles, retention and the server's
/// detail are the same strings About carried before, in the same order.
///
/// Ordered the way a reader needs it: who stands between the phone and the
/// roads, each payload, then how long someone else keeps it.
struct PrivacyDetailView: View {
    /// Read, not hardcoded: the imported sentence states these two numbers as fact.
    let matching: TrackingConfig.Matching

    var body: some View {
        List {
            Section {
                // The rest of the server's story. The first-run card carries
                // only the hop sentence, so this is where the detail lives
                // rather than being cut from the app (Chiu 2026-09-06).
                if let detail = PrivacyNoticeCopy.relayDetailKey(for: matching) {
                    Text(LocalizedStringKey(detail))
                }
                payload("privacy_imported_title", body: Text(PrivacyNoticeCopy.importedBody(for: matching)))
                payload("privacy_recorded_title", body: Text("privacy_recorded_body"))
                payload("privacy_tiles_title", body: Text("privacy_tiles_body"))
                Text("privacy_retention")
            }
            .font(.callout)
        }
        .navigationTitle("privacy_details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func payload(_ title: LocalizedStringKey, body: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            body
        }
        .padding(.vertical, 2)
    }
}
