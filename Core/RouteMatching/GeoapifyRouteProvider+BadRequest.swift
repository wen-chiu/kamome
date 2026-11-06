import Foundation

extension GeoapifyRouteProvider {
    /// **Which of the two geography answers a 400 is** (ADR 2026-09-23 (c)).
    ///
    /// Matched on the provider's own words, measured against the live endpoint
    /// through the Worker on 2026-09-23 with public landmark coordinates:
    ///
    /// | request | answer |
    /// |---|---|
    /// | Taoyuan airport → Miyako airport | `No path could be found for input` |
    /// | Miyako town → Sunayama beach | `No suitable edges near location. Please check…` |
    ///
    /// Only the second is matched; **every other 400 stays `.noRoadHere`**, which
    /// is what all of them were before the split. If the provider ever rewords the
    /// off-network message, beaches go back to being crossings — the old
    /// behaviour, never a new wrong one — and `RouteReconstructionTests` pins the
    /// wording so that shows up as a red test, not as planes over beaches.
    static func verdict(for400 message: String) -> RouteReconstruction {
        message.localizedCaseInsensitiveContains("no suitable edges") ? .offTheRoadNetwork : .noRoadHere
    }
}
