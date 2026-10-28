import Foundation

/// **「找出我的旅程」 pressed in 旅程** (#290, ADR
/// 2026-10-26-home-shows-a-newcomer-the-next-step). 旅程's empty state carries
/// 足跡's welcome card, and its button means what it means in 足跡: ask for the
/// library, then scan. Home shows 足跡 at the same moment, so the journeys are
/// found where they are listed.
///
/// §0 is unchanged: nothing is scanned or looked up until the person presses
/// the button or opens 足跡 (ADR 2026-09-30-footprints-sits-beside-journeys, Data 5).
extension JourneyDiscoveryModel {
    /// Called by Home as it switches to 足跡.
    /// - 足跡 not looked at yet: its first look asks (`firstLook()`), so the
    ///   library is asked for and scanned once, not by two callers at once.
    /// - Looked at, and nobody has answered: asks now.
    /// - Answered: nothing to do — 足跡 already lists the journeys, or shows the
    ///   way to Settings.
    ///
    /// Returns the asking task, when there is one, for a test to wait on.
    @discardableResult
    func findJourneys() -> Task<Void, Never>? {
        guard phase != .idle else {
            asksOnFirstLook = true
            return nil
        }
        guard access == .undetermined else { return nil }
        return Task { await requestAccessAndDiscover() }
    }

    /// 足跡's first appearance: reads whether the library may be read and
    /// scans if it may — or asks first, if 「找出我的旅程」 was pressed in 旅程.
    func firstLook() async {
        if asksOnFirstLook {
            asksOnFirstLook = false
            await requestAccessAndDiscover()
        } else {
            await refresh()
        }
    }
}
