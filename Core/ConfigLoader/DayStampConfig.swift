import Foundation

/// **The day stamp's timing** (Chiu 2026-10-28, ADR 2026-10-28-a-new-day-presses-a-stamp-into-the-film).
///
/// When the film's day turns, an ink stamp naming the new day presses into the
/// frame on the approach to that day's first stop, holds, and shrinks into the
/// HUD pill's day slot as the car arrives. It adds no film time: it rides on the
/// travel already there and, where that is short, on the arrival beat before the
/// photographs open. A turn with less room than `minS` gets no stamp, and the HUD
/// turns over as it always has.
///
/// Every value is **INFERRED** — a first cut, judged by Chiu from the film. Its
/// own type because `Export` sits at its file-length limit, as `TravelPacingConfig`.
public struct DayStampConfig: Decodable, Equatable {
    /// The HUD's previous day fades out, so two days are never in one frame.
    public let clearS: Double
    /// The ink presses in.
    public let pressS: Double
    /// The stamp holds, readable. The one phase that gives way when room is short.
    public let holdS: Double
    /// The stamp shrinks into the HUD pill's day slot.
    public let landS: Double
    /// The least room a turn needs for a stamp at all: clear, press and land at
    /// full length, and a shortened hold.
    public let minS: Double

    enum CodingKeys: String, CodingKey {
        case clearS = "clear_s"
        case pressS = "press_s"
        case holdS = "hold_s"
        case landS = "land_s"
        case minS = "min_s"
    }

    public init(clearS: Double, pressS: Double, holdS: Double, landS: Double, minS: Double) {
        self.clearS = clearS
        self.pressS = pressS
        self.holdS = holdS
        self.landS = landS
        self.minS = minS
    }

    /// No stamp: the default for hand-built test configs, which pin the films
    /// written before the stamp existed.
    public static let off = DayStampConfig(clearS: 0, pressS: 0, holdS: 0, landS: 0, minS: 0)

    /// Its full length, every phase at its configured value.
    public var totalS: Double { clearS + pressS + holdS + landS }

    public var isEnabled: Bool { pressS > 0 && landS > 0 && totalS.isFinite }
}
