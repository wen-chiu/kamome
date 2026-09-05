import Foundation
import KamomeConfig

/// **One source for the privacy copy, shared by both surfaces that show it** —
/// `AboutView` and `FirstRunNoticeView` (Chiu 2026-09-04: one string source, not
/// two, because two drift and the drifted one is still a legal statement about
/// what leaves a user's device).
///
/// Everything here is **derived from `TrackingConfig` rather than typed into the
/// copy**, which is the rule S3 already established for the two numbers in
/// `privacy_imported_body`: a sentence that cannot follow a configuration change
/// goes quietly untrue, and nothing fails.
enum PrivacyNoticeCopy {
    /// Which sentence describes where a journey's coordinates actually go.
    ///
    /// `api_key_required` is the discriminator because it *is* the topology:
    /// `true` says this build carries the Geoapify key and calls the provider
    /// itself; `false` says the key lives in Kamome's relay and the app calls
    /// that instead, which adds a hop the notice has to name. Reading the flag
    /// means the config flip (`Docs/release-readiness.md` S6) changes the
    /// sentence with it, rather than leaving the copy behind describing the old
    /// path.
    static func hopKey(for matching: TrackingConfig.Matching) -> String {
        matching.apiKeyRequired ? "privacy_hop_direct" : "privacy_hop_relay"
    }

    /// The imported payload — the only sentence carrying numbers, and both come
    /// from config so tuning either one cannot make the notice false.
    ///
    /// Localized here rather than in each view: two `String(localized:)` call
    /// sites formatting the same key with the same two arguments is one
    /// argument-order slip away from printing a garbage number on one screen and
    /// the right one on the other.
    static func importedBody(for matching: TrackingConfig.Matching) -> String {
        String.localizedStringWithFormat(
            String(localized: "privacy_imported_body"),
            matching.routeWaypointMinSpacingM,
            matching.chunkSize
        )
    }
}
