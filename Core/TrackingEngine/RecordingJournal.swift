import Foundation
import KamomeConfig

/// The write-ahead record of a live recording, so a trip survives the app
/// being terminated mid-journey (2026-09-24).
///
/// Until this existed a recording lived only in `TrackingEngine`'s memory and
/// reached the database on End Trip. Anything that ended the process first — a
/// swipe in the app switcher, iOS reclaiming memory, a TestFlight or iOS update,
/// a flat battery — lost the whole trip, silently. On a two-week journey that is
/// not an edge case.
///
/// **Why a journal of inputs rather than a snapshot of state:** the engine is a
/// pure, clock-free state machine, so feeding it the same start and the same
/// samples in the same order reproduces its state exactly — segments, stops,
/// dwell pause and all. That is what the GPX harness already relies on. The
/// journal therefore records only what `TrackingSession` fed the engine, and
/// recovery is `replay`. No engine internals are serialized, so the engine can
/// change without a migration.
///
/// Format: one line per event, comma-separated, numbers in Swift's shortest
/// round-trip form so a replayed `Double` is bit-identical. A line that does
/// not parse — the half-written last line of a killed process — is skipped.
///
///     start,1,<ts>,<vehicle>
///     s,<ts>,<lat>,<lon>,<hAcc>,<speed>,<course>,<alt>,<activity>
///     end,<ts>
///
/// Empty fields are nil. Activity is a kind letter (a/c/w/t) followed by 1 for
/// at-least-medium confidence or 0 for low, or empty when none was known.
///
/// ⚠️ The journal holds real positions (§0): it lives only on the device, next
/// to the database, and is deleted once the trip is saved.
public enum RecordingJournal {
    public static let formatVersion = 1

    public enum Entry: Equatable {
        case start(ts: Double, vehicle: VehicleType)
        case sample(LocationSample, MotionActivity?)
        case end(ts: Double)
    }

    // MARK: - Encoding

    public static func line(for entry: Entry) -> String {
        switch entry {
        case let .start(ts, vehicle):
            return "start,\(formatVersion),\(ts),\(vehicle.rawValue)"
        case let .sample(sample, activity):
            let fields: [String] = [
                "s",
                "\(sample.ts)",
                "\(sample.lat)",
                "\(sample.lon)",
                optional(sample.hAccM),
                optional(sample.speedMps),
                optional(sample.course),
                optional(sample.altitudeM),
                activity.map(encode) ?? ""
            ]
            return fields.joined(separator: ",")
        case let .end(ts):
            return "end,\(ts)"
        }
    }

    public static func parse(_ text: String) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { entry(from: $0) }
    }

    public static func entry<S: StringProtocol>(from line: S) -> Entry? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard let tag = fields.first else { return nil }
        switch tag {
        case "s":
            guard fields.count == 9,
                  let ts = Double(fields[1]), let lat = Double(fields[2]), let lon = Double(fields[3])
            else { return nil }
            let sample = LocationSample(
                ts: ts, lat: lat, lon: lon,
                hAccM: Double(fields[4]),
                speedMps: Double(fields[5]),
                course: Double(fields[6]),
                altitudeM: Double(fields[7])
            )
            return .sample(sample, activity(from: fields[8]))
        case "start":
            guard fields.count == 4, Int(fields[1]) == formatVersion,
                  let ts = Double(fields[2]), let vehicle = VehicleType(rawValue: String(fields[3]))
            else { return nil }
            return .start(ts: ts, vehicle: vehicle)
        case "end":
            guard fields.count == 2, let ts = Double(fields[1]) else { return nil }
            return .end(ts: ts)
        default:
            return nil
        }
    }

    // MARK: - Replay

    /// A recording rebuilt from its journal.
    public struct Recovered {
        /// In `.recording` or `.dwellPaused` — never finished, even when the
        /// journal carries an end: finishing is the caller's step, at `endedAt`.
        public let engine: TrackingEngine
        public let startedAt: Double
        /// Every sample the engine was fed, in order — the live HUD's path is
        /// built from exactly these, so a recovered HUD matches the lost one.
        public let samples: [LocationSample]
        /// Set when End Trip was pressed but the save never completed: the
        /// trip is to be saved as ending here, not resumed.
        public let endedAt: Double?
    }

    /// Rebuilds the engine a journal describes, or nil when there is no
    /// recording in it (no start line).
    ///
    /// Entries before the last `start` are ignored — a stale journal the app
    /// failed to delete must never leak into the next trip.
    public static func replay(_ entries: [Entry], config: TrackingConfig) -> Recovered? {
        guard let startIndex = entries.lastIndex(where: {
            if case .start = $0 { return true }
            return false
        }), case let .start(startedAt, vehicle) = entries[startIndex] else { return nil }

        let engine = TrackingEngine(config: config, vehicle: vehicle)
        engine.start(at: startedAt)
        var samples: [LocationSample] = []
        var endedAt: Double?
        for entry in entries[(startIndex + 1)...] {
            switch entry {
            case let .sample(sample, activity):
                guard endedAt == nil else { continue }
                engine.process(sample, activity: activity)
                samples.append(sample)
            case let .end(ts):
                endedAt = endedAt ?? ts
            case .start:
                continue
            }
        }
        return Recovered(engine: engine, startedAt: startedAt, samples: samples, endedAt: endedAt)
    }

    // MARK: - Private

    private static func optional(_ value: Double?) -> String {
        value.map { "\($0)" } ?? ""
    }

    private static func encode(_ activity: MotionActivity) -> String {
        let kind: String
        switch activity.kind {
        case .automotive: kind = "a"
        case .cycling: kind = "c"
        case .walking: kind = "w"
        case .stationary: kind = "t"
        }
        return kind + (activity.isAtLeastMediumConfidence ? "1" : "0")
    }

    private static func activity<S: StringProtocol>(from field: S) -> MotionActivity? {
        guard field.count == 2, let letter = field.first, let flag = field.last else { return nil }
        let kind: MotionActivity.Kind
        switch letter {
        case "a": kind = .automotive
        case "c": kind = .cycling
        case "w": kind = .walking
        case "t": kind = .stationary
        default: return nil
        }
        switch flag {
        case "1": return MotionActivity(kind: kind, isAtLeastMediumConfidence: true)
        case "0": return MotionActivity(kind: kind, isAtLeastMediumConfidence: false)
        default: return nil
        }
    }
}
