import Foundation
import KamomeConfig

/// **One track's beatmap** (`Docs/handoff-music-in-the-film.md` §2.2): its tempo
/// grid, its sections and where its last chord falls, measured once at the desk
/// by `Tools/kamome-beatmap.py` and never computed on the phone.
///
/// **The single schema.** The desk tool writes this JSON and this type decodes
/// it; `Tools/kamome_soundtrack_manifest.py` validates by the same rules, and
/// `SoundtrackManifestTests` holds the two to one set of fixtures — a manifest
/// either side refuses, the other refuses with the same code.
public struct SoundtrackManifest: Codable, Equatable {
    public enum Role: String, Codable {
        case intro, body, lift, peak, outro
    }

    /// A stretch of the track, on its bar grid. Bars count from the first
    /// downbeat, so bar `n` starts at `firstDownbeatS + n · barS`.
    public struct Section: Codable, Equatable {
        public let name: String
        public let startBar: Int
        public let bars: Int
        /// 1 (quiet) upward; the arrangement places the highest near the film's
        /// strongest moment.
        public let energy: Int
        public let role: Role
        /// Whether the section may play more than once in a row, which is how a
        /// film longer than the track is filled (§2.5 item 4).
        public let repeatable: Bool

        public var endBar: Int { startBar + bars }

        enum CodingKeys: String, CodingKey {
            case name, bars, energy, role, repeatable
            case startBar = "start_bar"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            startBar = try container.decode(Int.self, forKey: .startBar)
            bars = try container.decode(Int.self, forKey: .bars)
            energy = try container.decode(Int.self, forKey: .energy)
            role = try container.decode(Role.self, forKey: .role)
            repeatable = try container.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
        }

        public init(name: String, startBar: Int, bars: Int, energy: Int, role: Role, repeatable: Bool = false) {
            self.name = name
            self.startBar = startBar
            self.bars = bars
            self.energy = energy
            self.role = role
            self.repeatable = repeatable
        }
    }

    /// Where the track came from, so a kept take can be regenerated exactly.
    public struct Provenance: Codable, Equatable {
        public let engine: String
        public let commit: String?
        public let seed: Int?

        public init(engine: String, commit: String? = nil, seed: Int? = nil) {
            self.engine = engine
            self.commit = commit
            self.seed = seed
        }
    }

    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let style: String
    public let mood: String
    /// The audio file's name beside this manifest. Audio is never committed
    /// (bundle vs download is still open, handoff §7 item 6).
    public let file: String
    /// The audio file's length, measured — what every section must fit inside.
    public let durationS: Double
    public let bpm: Double
    public let beatsPerBar: Int
    public let firstDownbeatS: Double
    /// The largest departure of the measured tempo from `bpm` across the track.
    public let tempoDriftBpm: Double
    public let sections: [Section]
    /// False until Chiu has listened and signed the proposed sections (§5: the
    /// tool writes them, a human confirms them).
    public let sectionsConfirmed: Bool
    /// The bar line the last chord lands on — anchored to the end card.
    public let finalHitBar: Int
    /// How long the track rings on after the final hit.
    public let tailS: Double
    public let integratedLufs: Double
    public let truePeakDbtp: Double
    public let provenance: Provenance

    enum CodingKeys: String, CodingKey {
        case id, style, mood, file, bpm, sections, provenance
        case schemaVersion = "schema_version"
        case durationS = "duration_s"
        case beatsPerBar = "beats_per_bar"
        case firstDownbeatS = "first_downbeat_s"
        case tempoDriftBpm = "tempo_drift_bpm"
        case sectionsConfirmed = "sections_confirmed"
        case finalHitBar = "final_hit_bar"
        case tailS = "tail_s"
        case integratedLufs = "integrated_lufs"
        case truePeakDbtp = "true_peak_dbtp"
    }

    // MARK: - The grid

    public var beatS: Double { 60 / bpm }
    public var barS: Double { beatS * Double(beatsPerBar) }

    /// Source time of bar line `bar`.
    public func timeS(bar: Int) -> Double { firstDownbeatS + Double(bar) * barS }

    public var finalHitS: Double { timeS(bar: finalHitBar) }

    /// The ending: the one section whose role is `outro`, and the last.
    public var outro: Section? { sections.last.flatMap { $0.role == .outro ? $0 : nil } }
}

extension SoundtrackManifest {
    public init(
        id: String, style: String, mood: String, file: String, durationS: Double,
        bpm: Double, beatsPerBar: Int, firstDownbeatS: Double, tempoDriftBpm: Double,
        sections: [Section], sectionsConfirmed: Bool, finalHitBar: Int, tailS: Double,
        integratedLufs: Double, truePeakDbtp: Double, provenance: Provenance
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.style = style
        self.mood = mood
        self.file = file
        self.durationS = durationS
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.firstDownbeatS = firstDownbeatS
        self.tempoDriftBpm = tempoDriftBpm
        self.sections = sections
        self.sectionsConfirmed = sectionsConfirmed
        self.finalHitBar = finalHitBar
        self.tailS = tailS
        self.integratedLufs = integratedLufs
        self.truePeakDbtp = truePeakDbtp
        self.provenance = provenance
    }
}

// MARK: - Validation

/// Why a manifest was refused. Each `code` is the same string
/// `Tools/kamome_soundtrack_manifest.py` reports, so a fixture's expected
/// refusal is written once and checked on both sides.
public struct SoundtrackManifestError: Error, Equatable, CustomStringConvertible {
    public let code: String
    public let description: String
}

extension SoundtrackManifest {
    /// Decodes and validates in one step: a manifest that decodes but does not
    /// validate is never handed on.
    public static func load(from data: Data, limits: TrackingConfig.Soundtrack) throws -> SoundtrackManifest {
        let manifest = try JSONDecoder().decode(SoundtrackManifest.self, from: data)
        try manifest.validate(limits: limits)
        return manifest
    }

    /// Refuses a manifest the arrangement could not honour, or a track the desk
    /// should never have kept. Throws the **first** rule broken, in the order
    /// the Python validator checks them.
    public func validate(limits: TrackingConfig.Soundtrack) throws {
        try validateIdentity()
        try validateGrid()
        try validateSections()
        try validateEnding()
        try validateMeasurements(limits)
    }

    private func refuse(_ code: String, _ why: String) -> SoundtrackManifestError {
        SoundtrackManifestError(code: code, description: "\(id): \(why)")
    }

    private func validateIdentity() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw refuse("schema_version", "schema \(schemaVersion), expected \(Self.schemaVersion)")
        }
        guard ![id, style, mood, file].contains(where: \.isEmpty) else {
            throw refuse("identity", "id, style, mood and file must all be named")
        }
    }

    private func validateGrid() throws {
        guard bpm.isFinite, bpm > 0, beatsPerBar >= 1, firstDownbeatS.isFinite, firstDownbeatS >= 0,
              durationS.isFinite, durationS > 0 else {
            throw refuse("grid", "bpm, beats per bar, first downbeat and duration must be positive")
        }
    }

    private func validateSections() throws {
        guard !sections.isEmpty else { throw refuse("sections_empty", "no sections") }
        for section in sections where section.bars < 1 || section.startBar < 0 || section.energy < 1 {
            throw refuse("section_shape", "\(section.name) needs a start ≥ 0, bars ≥ 1 and energy ≥ 1")
        }
        for (previous, next) in zip(sections, sections.dropFirst()) where next.startBar < previous.endBar {
            throw refuse("section_overlap", "\(next.name) starts inside \(previous.name)")
        }
        if let last = sections.last, timeS(bar: last.endBar) > durationS + Self.fitSlackS {
            throw refuse("section_past_end", "\(last.name) ends after the file does")
        }
        guard sections.contains(where: { $0.repeatable && ($0.role == .body || $0.role == .peak) }) else {
            throw refuse("no_repeatable", "no repeatable body or peak section, so no film longer than the track")
        }
    }

    private func validateEnding() throws {
        guard let outro, sections.filter({ $0.role == .outro }).count == 1 else {
            throw refuse("outro", "exactly one outro, and it must be the last section")
        }
        guard finalHitBar >= outro.startBar, finalHitBar <= outro.endBar else {
            throw refuse("final_hit", "the final hit is not inside the outro")
        }
        guard tailS.isFinite, tailS >= 0, finalHitS + tailS <= durationS + Self.fitSlackS else {
            throw refuse("tail", "the final hit and its tail run past the file")
        }
    }

    private func validateMeasurements(_ limits: TrackingConfig.Soundtrack) throws {
        guard abs(integratedLufs - limits.targetLufs) <= limits.loudnessToleranceLu else {
            throw refuse("loudness", "\(integratedLufs) LUFS, target \(limits.targetLufs) ± \(limits.loudnessToleranceLu)")
        }
        guard truePeakDbtp <= limits.truePeakMaxDbtp else {
            throw refuse("true_peak", "true peak \(truePeakDbtp) dBTP over \(limits.truePeakMaxDbtp)")
        }
        guard tempoDriftBpm >= 0, tempoDriftBpm <= limits.tempoDriftMaxBpm else {
            throw refuse("tempo_drift", "tempo drifts \(tempoDriftBpm) BPM, at most \(limits.tempoDriftMaxBpm)")
        }
    }

    /// One audio sample at 8 kHz: a section's bar-line arithmetic may land a
    /// rounding error past a duration measured to the sample. Not a tunable —
    /// it is float slack, not a choice.
    private static let fitSlackS = 1.0 / 8_000
}
