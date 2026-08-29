import Foundation

/// Which appearance a film is rendered in — **one value, chosen once, for the
/// whole export.**
///
/// It selects two things that must never disagree: the palette
/// `RecapOverlayRenderer` draws Kamome's own graphics in
/// (`RecapStyle.modernMinimal(_:)`), and the trait the base map is asked for
/// (`MapKitSnapshotProvider`). They disagreed once already and it cost a defect:
/// the glow pass was tuned to read as *light* over the dark souvenir map, and
/// when the 2026-08-15 substrate ADR moved the film onto Apple Maps' light base
/// the same translucent stroke composited *darker* than the terrain and rang the
/// trail with a shadow for six days of renders (`a58942d`). Same code, opposite
/// effect, because the palette and the base map had no value in common.
///
/// **Why this is a domain type and not `MapKitSnapshotProvider.Appearance`,
/// which it replaces.** The trail, the dashes, the grade and the chrome are
/// Kamome's graphics drawn *over* whatever the base map returned — not the base
/// map's colours. A style that reached into a renderer's nested enum to pick its
/// own palette would point the dependency the wrong way (`PO.md`: the Story layer
/// must not depend on the current rendering substrate). Here the renderer depends
/// on the domain value, which is the direction the project protects. It also
/// keeps the provider's public surface free of UIKit, which is what the enum it
/// replaces existed for — MapKit runs on platforms UIKit does not.
///
/// **Reproducibility** (`Docs/decisions.md` 2026-08-15, "Export variation enters
/// as a seed, never as randomness"). This is ambient device state, so it is
/// handled the way that ADR handles a seed: captured at the composition boundary
/// the instant the user taps export, constant for the render, never read from the
/// environment inside the render loop. The half that is **not** met is
/// persistence — no export record exists to store it in — so the resolved value
/// is written into the film's log line instead, and the gap is recorded in
/// `Docs/eng-session-appearance.md` §4.1 rather than assumed away.
public enum RecapAppearance: String, Sendable, CaseIterable {
    case light
    case dark
}
