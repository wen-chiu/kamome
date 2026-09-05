import Foundation
import KamomeConfig

/// The one-time notice that tells a user real trip coordinates leave this
/// device — Chiu 2026-09-04, answering the question `Docs/release-readiness.md`
/// S3 left open (*"does the import flow warn at the point of import?"*). His
/// answer is narrower than the question: **tell the user once, on first run,
/// remember it, and never show it again.**
///
/// **This informs; it does not ask.** There is deliberately no "decline"
/// (ADR 2026-09-05): a refusal that switches nothing off is a worse lie than no
/// question at all, and the control the app really offers is the one
/// `privacy_control` already names — you decide what is sent by deciding what to
/// import.
///
/// **Gated on this build being able to send anything.** `matching.base_url` is
/// `""` in the shipped config, so nothing leaves the device yet and a notice
/// shown now would describe a state that has not arrived — the exact mistake
/// `Docs/release-readiness.md` S3b is still cleaning up after. The endpoint read
/// here is the *effective* one, after `AppConfig.applyingRoutingKey` has emptied
/// it for a build that carries no key, so "this build can send" and "the user
/// has been told" cannot disagree. **The config flip is therefore what publishes
/// the notice**, on the first launch after it ships, for new and existing users
/// alike.
enum FirstRunNotice {
    /// Raise this **only when what is sent, or where it goes, materially
    /// changes** — never for a typo or a translation pass. Everyone who
    /// acknowledged an older version is then told again. The wording is still
    /// Chiu's to rule on (`Docs/release-readiness.md` S2/S3), which is why the
    /// stored fact is a version and not a Bool.
    static let version = 1

    private static let key = "kamome.privacyNoticeAcknowledgedVersion"

    /// An unset default reads as 0, so a fresh install is told — and so is a
    /// reinstall, which takes `UserDefaults` with it. Telling someone twice is
    /// the safe direction; telling them never is the one that breaks §0's
    /// promise of honest disclosure.
    static func shouldPresent(
        matching: TrackingConfig.Matching,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !matching.baseURL.isEmpty else { return false }
        return defaults.integer(forKey: key) < version
    }

    /// Called from the notice's own button, never from `onDisappear`: the stored
    /// fact is "this user was told and closed it", and a swipe that happened to
    /// dismiss a sheet is not that.
    static func acknowledge(defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: key)
    }
}
