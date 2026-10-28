import Foundation
import KamomeConfig

/// **When the film's day turns, a stamp says so** (Chiu 2026-10-28, ADR
/// 2026-10-28-a-new-day-presses-a-stamp-into-the-film).
///
/// The day used to turn over silently: the HUD's text changed on arrival and
/// nothing else did. Now an ink stamp naming the new day presses in on the
/// approach to that day's first stop, holds, and shrinks into the HUD pill's day
/// slot, landing as the car arrives — the instant the HUD has always turned over.
///
/// **No new day rule** (ADR 2026-10-26-a-one-day-film-names-no-day): the day is
/// the stop's own `dayLabel`, on the same clock, and a one-day film's labels are
/// all `""`, so it has no turn and no stamp. The film's first day has none either:
/// nothing turns, and the title card opens the film.
///
/// **No added film time.** A stamp rides on what is already there — the previous
/// stop's pull-away, the travel into the stop and, when those are short, the
/// arrival beat before the photographs open — and never over a photograph, the title card, the boarding pass, a
/// crossing or the end card. A turn with less room than `min_s` keeps the silent
/// turn-over, and the build log says which stop index lost it (§0: never where).
struct DayStampWindow: Equatable {
    let label: String
    let previousLabel: String
    /// The first stop of the new day.
    let stopIndex: Int
    /// The HUD's previous day starts to fade.
    let startS: Double
    let pressStartS: Double
    /// Pressed: the stamp holds from here until `landStartS`.
    let pressEndS: Double
    let landStartS: Double
    /// Landed: the HUD shows the new day from here.
    let endS: Double
}

extension LinearTimeline {
    /// The stamp at `time`, if one is playing.
    func dayStamp(atTime time: Double) -> RecapDayStamp? {
        guard let window = dayStampWindows.first(where: { $0.startS <= time && time < $0.endS }) else { return nil }
        func progress(_ from: Double, _ until: Double) -> Double {
            guard until > from else { return time >= until ? 1 : 0 }
            return min(max((time - from) / (until - from), 0), 1)
        }
        return RecapDayStamp(
            label: window.label, previousLabel: window.previousLabel,
            clear: progress(window.startS, window.pressStartS),
            press: progress(window.pressStartS, window.pressEndS),
            land: progress(window.landStartS, window.endS)
        )
    }

    /// Every turn of the day the film can afford a stamp for, in film order.
    func plannedDayStampWindows(_ config: DayStampConfig) -> [DayStampWindow] {
        guard config.isEnabled else { return [] }
        let ordered = holds.filter { stops.indices.contains($0.stopIndex) }.sorted { $0.startS < $1.startS }
        var current = stops.first?.dayLabel ?? ""
        var previousEndS = 0.0
        var windows: [DayStampWindow] = []
        for hold in ordered {
            let label = stops[hold.stopIndex].dayLabel
            // The previous stop's photographs close a park ramp before its scene
            // does, as the car pulls away: from there nothing is over a photo.
            defer { previousEndS = activeScene(atTime: hold.startS)?.hold == hold ? deckWindow(hold).end : hold.endS }
            guard label != current else { continue }
            defer { current = label }
            guard !label.isEmpty, !current.isEmpty else { continue }
            if let window = dayStampWindow(config, for: hold, label: label, previous: current, after: previousEndS) {
                windows.append(window)
            } else {
                KamomeLog.recap.notice("""
                    day stamp: no room before stop \(hold.stopIndex, privacy: .public) — the HUD turns over unstamped
                    """)
            }
        }
        return windows
    }

    /// One turn's stamp: landing on arrival when the approach has room, later
    /// (inside the arrival beat) when it has not, and with a shorter hold when
    /// even that is short. Nil below `min_s`.
    private func dayStampWindow(
        _ config: DayStampConfig, for hold: CameraPath.Hold, label: String, previous: String, after previousEndS: Double
    ) -> DayStampWindow? {
        let floor = dayStampFloor(before: hold.startS, previousEndS: previousEndS)
        // Never over a photograph: landed before this stop's deck opens.
        var ceiling = activeScene(atTime: hold.startS)?.hold == hold ? deckWindow(hold).start : hold.endS
        ceiling = min(ceiling, durationS - endCardS)
        let room = ceiling - floor
        guard room >= config.minS, room > 0 else { return nil }
        let fixed = config.clearS + config.pressS + config.landS
        let holdS = min(config.holdS, room - fixed)
        guard holdS >= 0 else { return nil }
        let total = fixed + holdS
        let startS = max(floor, hold.startS - total)
        let pressStartS = startS + config.clearS
        let pressEndS = pressStartS + config.pressS
        let landStartS = pressEndS + holdS
        return DayStampWindow(
            label: label, previousLabel: previous, stopIndex: hold.stopIndex, startS: startS,
            pressStartS: pressStartS, pressEndS: pressEndS, landStartS: landStartS, endS: landStartS + config.landS
        )
    }

    /// The earliest a stamp may start before a stop arrived at `arrivalS`: after
    /// the previous stop's photographs, the title card and the opening, and after
    /// any crossing, flight move or departure cut on the way in.
    private func dayStampFloor(before arrivalS: Double, previousEndS: Double) -> Double {
        var floor = max(previousEndS, titleCardS, openingS)
        var blocked: [ClosedRange<Double>] = path.crossingBeatWindowsS + path.arcs.map { $0.startS...$0.endS }
        if let cut = departureCut { blocked.append(cut.startS...cut.endS) }
        for window in blocked where window.lowerBound < arrivalS {
            floor = max(floor, window.upperBound)
        }
        return floor
    }

    /// The day the HUD's line is laid out with: the stamp's while one plays, so
    /// the pill does not change width under it as it lands.
    func hudDayLabel(atTime time: Double, stamp: RecapDayStamp?) -> String {
        stamp?.label ?? dayLabel(atTime: time)
    }
}
