import KamomeTrackingEngine
import SwiftUI

/// The journey's places and the travel between them, as one wrapping sentence.
/// Moved out of `JourneyEntry` when it learnt to fold legs (#265).
enum JourneyRouteText {
    /// A named place on the route line, and the glyph for the travel that
    /// reached it from the named place before — nil for the first.
    struct Step: Equatable {
        let name: String
        let glyph: String?
    }

    /// A stop as the route line reads it: its name, when it has a real one,
    /// and when it was there.
    struct Stop {
        let name: String?
        let arrivedAt: Double
        let departedAt: Double?
    }

    /// **The steps, names and legs folded together** (#265). A repeated name
    /// is one step ("Whitehorse › Whitehorse" says less than "Whitehorse"),
    /// and the glyph into the next name is the travel from the *last* stop of
    /// that name to it, folded by `StoryLegFolding` — the rule the diary
    /// draws its connectors by — so a local wander around one town is not
    /// drawn as the way to the next. An unnamed stop is skipped; the travel
    /// through it still counts. A crossing anywhere in that travel is the
    /// plane; otherwise the first mode.
    ///
    /// The glyph used to be `legModes[i − 1]`: one entry per *segment*, while
    /// the names had been folded and filtered, so the two lists drifted apart.
    static func steps(stops: [Stop], legs: [StoryLegFolding.Piece]) -> [Step] {
        var steps: [Step] = []
        // The departure of the latest stop carrying the last step's name.
        var travelFrom = 0.0
        for stop in stops {
            guard let name = stop.name else { continue }
            if let last = steps.last, last.name == name {
                travelFrom = stop.departedAt ?? stop.arrivedAt
                continue
            }
            let glyph: String? = steps.isEmpty ? nil : {
                guard let folded = StoryLegFolding.fold(legs, from: travelFrom, to: stop.arrivedAt) else {
                    return TransportGlyph.symbol(for: .unknown)
                }
                return folded.isCrossing
                    ? TransportGlyph.crossing : TransportGlyph.symbol(for: folded.modes.first ?? .unknown)
            }()
            steps.append(Step(name: name, glyph: glyph))
            travelFrom = stop.departedAt ?? stop.arrivedAt
        }
        return steps
    }

    static func text(steps: [Step], legModes: [String], stopCount: Int, limit: Int) -> Text {
        guard let first = steps.first else { return unnamed(legModes: legModes, stopCount: stopCount) }
        let shown = steps.prefix(limit)
        var result = Text(verbatim: first.name)
        for step in shown.dropFirst() {
            result = result
                + Text(verbatim: "  ")
                + Text(Image(systemName: step.glyph ?? TransportGlyph.symbol(for: .unknown)))
                + Text(verbatim: "  ")
                + Text(verbatim: step.name)
        }
        guard steps.count > shown.count else { return result }
        return result + Text(verbatim: "  +\(steps.count - shown.count)")
    }

    /// Three stops around one town all answer "Whitehorse", and a line reading
    /// "Whitehorse › Whitehorse › Whitehorse" says less than one that reads
    /// "Whitehorse". The stops are still three; only the naming repeats.
    static func collapsingRepeats(_ names: [String]) -> [String] {
        names.reduce(into: [String]()) { result, name in
            if result.last != name { result.append(name) }
        }
    }

    /// A journey nobody has opened yet has no geocoded stops. It says how many
    /// places it holds and how it moved between them, which is true, rather
    /// than inventing names it does not have.
    private static func unnamed(legModes: [String], stopCount: Int) -> Text {
        var result = Text(String.localizedStringWithFormat(String(localized: "journey_places"), stopCount))
        for mode in orderedDistinct(legModes) {
            result = result + Text(verbatim: "  ") + Text(Image(systemName: TransportGlyph.symbol(forRawMode: mode)))
        }
        return result
    }

    private static func orderedDistinct(_ modes: [String]) -> [String] {
        var seen: Set<String> = []
        return modes.filter { seen.insert($0).inserted }
    }
}
