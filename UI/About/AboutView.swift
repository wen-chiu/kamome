import KamomeConfig
import SwiftUI

/// The licence and privacy surface — `Docs/release-readiness.md` S2 and S3.
///
/// **Attribution is a licence condition, not copy.** Geoapify attribution is
/// mandatory on the free plan, in the format "Powered by Geoapify" with a link,
/// and OpenStreetMap attribution is always required. Chiu decided 2026-08-17
/// that both live in the app's *interface* and never in the rendered film
/// (`Docs/pre-launch.md`) — nothing here may be drawn into the video.
///
/// **The privacy notice is an honest declaration** (ADR 2026-08-20 (c)), so
/// every sentence was checked against the code rather than against an intention:
///
/// - The two payloads are described separately because they are not the same
///   payload, and "start and end coordinates" is untrue of both.
/// - The thinning distance and the per-leg cap are read from `TrackingConfig`
///   rather than typed into the copy, so tuning either one cannot quietly make
///   the notice false.
/// - The recorded-trip paragraph describes what `RouteMatchService` actually
///   does today, which is **not** what `Docs/pre-launch.md`'s payload table
///   says. See `HANDOFF.md` — that conflict is Chiu's to settle, and until he
///   does, the sentence that matches the code is the honest one to ship.
///
/// ⏳ **The wording and the placement are Chiu's and are not ruled on yet.**
/// This ships so the obligation is met rather than deferred; the open half is
/// carried in `Docs/release-readiness.md` S2/S3. Visual craft is `DESIGNER.md`'s.
struct AboutView: View {
    /// Read, not hardcoded: the notice states these two numbers as fact.
    let matching: TrackingConfig.Matching
    @Environment(\.dismiss) private var dismiss

    /// Licence targets, deliberately not in `TrackingConfig.json`. Rule 7 governs
    /// *tunables*; changing either of these is a licence breach, not a tuning
    /// decision, and a key someone may edit is the wrong shape for that.
    private static let geoapify = URL(string: "https://www.geoapify.com/")!
    private static let openStreetMap = URL(string: "https://www.openstreetmap.org/copyright")!

    var body: some View {
        NavigationStack {
            List {
                attributionSection
                privacySection
            }
            .navigationTitle("about_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("about_close") { dismiss() }
                }
            }
        }
    }

    /// S2. The two rows are the obligation; the footer is the explanation, and
    /// the obligation does not depend on it.
    private var attributionSection: some View {
        Section {
            // "Powered by Geoapify" is the format the free plan requires, so it
            // is the same string in both languages — a translated brand
            // attribution would no longer be the required format.
            Link(destination: Self.geoapify) {
                linkRow("attribution_geoapify")
            }
            Link(destination: Self.openStreetMap) {
                linkRow("attribution_osm")
            }
        } header: {
            Text("attribution_header")
        } footer: {
            Text("attribution_note")
        }
    }

    /// S3. Ordered the way a reader needs it: what stays, then each payload,
    /// then how long someone else keeps it, then what the reader controls.
    private var privacySection: some View {
        Section {
            Text("privacy_intro")
            payload("privacy_imported_title", body: importedBody)
            payload("privacy_recorded_title", body: Text("privacy_recorded_body"))
            Text("privacy_retention")
            Text("privacy_control")
            Text("privacy_share")
        } header: {
            Text("privacy_header")
        }
        .font(.callout)
    }

    /// The imported payload is the only sentence carrying numbers, and both come
    /// from config so the copy cannot outlive a tuning change.
    private var importedBody: Text {
        Text(String.localizedStringWithFormat(
            String(localized: "privacy_imported_body"),
            matching.routeWaypointMinSpacingM,
            matching.chunkSize
        ))
    }

    private func payload(_ title: LocalizedStringKey, body: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            body
        }
        .padding(.vertical, 2)
    }

    private func linkRow(_ key: LocalizedStringKey) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.forward.square")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }
}
