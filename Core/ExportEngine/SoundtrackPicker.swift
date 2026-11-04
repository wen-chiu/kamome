import Foundation
import KamomeConfig

/// The three moods a brief is written in (`Tools/kamome_music_briefs.py`), as a
/// manifest's `mood` names them.
public enum SoundtrackMood: String, CaseIterable, Sendable {
    /// 出發 — bright, hopeful.
    case depart
    /// 巡航 — calm, steady.
    case cruise
    /// 壯闊 — grand.
    case epic
}

/// **What the picker knows about a film** (`Docs/handoff-music-in-the-film.md`
/// §2.3). Built by the app after the timeline is planned — ExportEngine never
/// sees the database. Holds a country code, which is location-derived: it is
/// read on the device and never logged (§4.4).
public struct SoundtrackContext: Equatable, Sendable {
    /// ISO code → share of the film's stop time in that country.
    public let countryShare: [String: Double]
    /// The country of the film's last stop: what a flight film is about, and
    /// who wins a tie.
    public let destinationCountry: String?
    public let photoMood: PhotoMood
    public let filmType: RecapFilmType
    public let durationS: Double
    public let appearance: RecapAppearance
    /// From the trip's id: the same trip always gets the same take.
    public let seed: UInt64

    public init(
        countryShare: [String: Double], destinationCountry: String?, photoMood: PhotoMood,
        filmType: RecapFilmType, durationS: Double, appearance: RecapAppearance, seed: UInt64
    ) {
        self.countryShare = countryShare
        self.destinationCountry = destinationCountry
        self.photoMood = photoMood
        self.filmType = filmType
        self.durationS = durationS
        self.appearance = appearance
        self.seed = seed
    }

    /// FNV-1a over the id's UTF-8 — stable across launches and devices, which
    /// Swift's `hashValue` is not.
    public static func seed(tripId: String) -> UInt64 {
        tripId.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}

extension LinearTimeline {
    /// **Film time per country**, from the stops' holds: what the picker's
    /// style is read from. A film that flies to its destination counts only the
    /// stops after the flight — the home end of a type-2 film is not the trip
    /// (§2.3). Stops with no country are not counted.
    public func soundtrackCountries() -> (share: [String: Double], destination: String?) {
        let landedS = filmType.hasDestinationAbroad ? path.crossingBeatWindowsS.first?.upperBound : nil
        var seconds: [String: Double] = [:]
        for hold in holds where hold.stopIndex < stops.count && hold.startS >= (landedS ?? -.infinity) {
            guard let code = stops[hold.stopIndex].countryCode else { continue }
            seconds[code, default: 0] += hold.endS - hold.startS
        }
        let total = seconds.values.reduce(0, +)
        let share = total > 0 ? seconds.mapValues { $0 / total } : [:]
        return (share, stops.last(where: { $0.countryCode != nil })?.countryCode)
    }
}

/// One track the picker offers, with the mood it was chosen for.
public struct SoundtrackChoice: Equatable {
    public let manifest: SoundtrackManifest
    public let mood: SoundtrackMood
    public let score: Double
}

/// **Which music, decided by us** (§2.3): the style from the country, the mood
/// from the photographs and the film's shape, the take from the seed. Pure and
/// deterministic — no ML, no network (spec §7).
public enum SoundtrackPicker {
    /// The picker's answer: the tracks in order, best first, and whether the
    /// trip's own style had no track that fits, so another style plays.
    public struct Ranking: Equatable {
        public let choices: [SoundtrackChoice]
        /// True when the trip's style had nothing that fits this film and the
        /// ranking was filled from `unlisted_style` (then the whole catalog).
        /// A declared fallback: the app logs it, without naming either style.
        public let styleFellBack: Bool
    }

    /// **The style** (§2.3 item 1): the country with the most film time picks
    /// it; a flight film and a tie go to the destination. A country not in the
    /// table, or no country at all, plays `unlisted_style`.
    public static func style(for context: SoundtrackContext, config: TrackingConfig.Soundtrack) -> String {
        let country: String?
        if context.filmType.hasDestinationAbroad, let destination = context.destinationCountry {
            country = destination
        } else if let most = context.countryShare.values.max() {
            let tied = context.countryShare.filter { $0.value >= most - 1e-9 }.map(\.key)
            country = tied.contains { $0 == context.destinationCountry } ? context.destinationCountry : tied.min()
        } else {
            country = nil
        }
        return country.flatMap { code in
            config.countryStyles.first { $0.countries.contains(code) }?.style
        } ?? config.unlistedStyle
    }

    /// **Each mood's score** (§2.3 item 2). Photograph terms count only when
    /// some photograph was measured: an unmeasured film is not a dull one.
    public static func moodScores(
        for context: SoundtrackContext, config: TrackingConfig.Soundtrack
    ) -> [SoundtrackMood: Double] {
        let weights = config.mood
        let photos = context.photoMood
        var depart = weights.baseDepart
        var cruise = weights.baseCruise
        var epic = weights.baseEpic
        if photos.photoCount > 0 {
            let vividness = (photos.luminance + photos.saturation) / 2 - weights.vividnessPivot
            depart += weights.peopleDepart * photos.peopleShare
                + weights.vividDepart * max(vividness, 0) + weights.warmthDepart * max(photos.warmth, 0)
            cruise += weights.nightCruise * photos.nightShare
                + weights.dullCruise * max(-vividness, 0) + weights.warmthDepart * max(-photos.warmth, 0)
            epic += weights.landscapeEpic * photos.landscapeShare
        }
        if context.filmType.hasDestinationAbroad { epic += weights.flightEpic }
        if context.durationS >= weights.longFilmS { epic += weights.longFilmEpic }
        if context.appearance == .dark { cruise += weights.darkCruise }
        return [.depart: depart, .cruise: cruise, .epic: epic]
    }

    /// **The tracks for this film, best first.** One take per mood comes first,
    /// in the order the moods scored, so the player's 「換音樂」 offers three
    /// different feelings; the other takes follow. Within a mood the take is
    /// chosen by `seed`. A track that cannot fill the film is never offered:
    /// one with no repeatable section for a film longer than it (§2.5 item 4),
    /// or one the arrangement refuses for these cues.
    public static func rank(
        catalog: [SoundtrackManifest], context: SoundtrackContext, cues: [FilmCue],
        config: TrackingConfig.Soundtrack
    ) -> Ranking {
        let fitting = catalog.filter { fits($0, context: context, cues: cues, config: config) }
        let style = style(for: context, config: config)
        var styleFellBack = false
        var pool = fitting.filter { $0.style == style }
        if pool.isEmpty {
            styleFellBack = true
            pool = fitting.filter { $0.style == config.unlistedStyle }
            if pool.isEmpty { pool = fitting }
        }
        let scores = moodScores(for: context, config: config)
        let moods = SoundtrackMood.allCases.sorted { (scores[$0] ?? 0) > (scores[$1] ?? 0) }
        var first: [SoundtrackChoice] = []
        var rest: [SoundtrackChoice] = []
        for mood in moods {
            let takes = pool.filter { $0.mood == mood.rawValue }.sorted { $0.id < $1.id }
            guard !takes.isEmpty else { continue }
            let pick = Int(context.seed % UInt64(takes.count))
            for (index, take) in takes.enumerated() {
                let choice = SoundtrackChoice(manifest: take, mood: mood, score: scores[mood] ?? 0)
                if index == pick { first.append(choice) } else { rest.append(choice) }
            }
        }
        return Ranking(choices: first + rest, styleFellBack: styleFellBack)
    }

    /// Whether `manifest` can carry this film: the literal §2.5 item 4 filter,
    /// then the arrangement itself, which is cheap (under 3 ms, §4.1a).
    static func fits(
        _ manifest: SoundtrackManifest, context: SoundtrackContext, cues: [FilmCue], config: TrackingConfig.Soundtrack
    ) -> Bool {
        guard SoundtrackMood(rawValue: manifest.mood) != nil else { return false }
        if context.durationS > manifest.durationS, !manifest.sections.contains(where: \.repeatable) { return false }
        return (try? SoundtrackArrangement.plan(
            manifest: manifest, cues: cues, durationS: context.durationS, config: config
        )) != nil
    }
}

/// **What a finished film keeps so its music can change later** (§3.2): the
/// cue sheet it was cut with and the picker's ranking. The timeline is never
/// stored, and the film's picture is frozen in its file, so the sheet the film
/// was made with is the one any later soundtrack must be cut to — a fresh one
/// from a trip edited since would cut music to a different film. Kinds,
/// times, stop indices and track ids only: no coordinate, name or country.
public struct FilmSoundtrackBasis: Codable, Equatable {
    /// Bumped when what a stored basis means changes, so an old film's basis is
    /// read as the version it was written under (`film.soundtrack_plan_version`).
    public static let planVersion = 1

    public let cues: [FilmCue]
    /// Track ids, best first, as `SoundtrackPicker.rank` ordered them.
    public let ranking: [String]

    public init(cues: [FilmCue], ranking: [String]) {
        self.cues = cues
        self.ranking = ranking
    }
}
