import Foundation

/// How long a recap runs and how its time is shared between stops.
///
/// **Why this exists** (Chiu 2026-08-08). Pacing used to be selected by whether
/// `establishing` — the installed vector-tile region's extent — was nil. Two
/// unrelated facts shared one parameter: *which tiles are on the device* (a
/// rendering fact, true only of the MapLibre substrate) and *how long this film
/// should be* (a story fact, true of the trip).
///
/// The coupling was invisible in tests because the deterministic harnesses wanted
/// a short fixed film and passing nil happened to give them one. On real data it
/// meant any trip no installed region covered came out at the retired flat
/// `export.target_duration_s` with no prologue — a six-day trip as a 30-second
/// film, for a reason that had nothing to do with the trip.
///
/// Naming the choice makes each side say what it means: a harness asks for
/// `.fixed` because it wants a known length, and the product asks for
/// `.contentDerived` because a film should be as long as its content justifies.
/// `establishing` is left meaning only what it says.
public enum RecapPacing: Equatable {
    /// The shipped path: `RecapDurationPlan` sizes the film from its own content —
    /// how many stops, how many photographs each carries — and fits it into the
    /// `total_duration_min_s … max_s` window, with the opening prologue included.
    case contentDerived

    /// A film of exactly `totalS` seconds with **no prologue**, for harnesses that
    /// need a known length so a golden frame means something.
    ///
    /// No prologue means `openingS` is 0, so `zoom_transition_s` never enters the
    /// opening and the subject-arrival ramp collapses to (0, 0) — the vehicle is
    /// on screen from the first frame. That is the same behaviour a nil
    /// `establishing` used to produce, now stated rather than inferred.
    case fixed(totalS: Double)
}

extension RecapPacing {
    /// The film's length when it is fixed, else nil — `CameraPath` falls back to
    /// `export.target_duration_s` for nil, which is what `.fixed` callers used to
    /// rely on implicitly.
    var fixedTotalS: Double? {
        switch self {
        case .contentDerived: return nil
        case let .fixed(totalS): return totalS
        }
    }
}
