import Foundation

extension TrackingConfig {
    /// **The film's music** (ADR 2026-11-03-music-leaves-deferred-and-every-film-has-it,
    /// `Docs/handoff-music-in-the-film.md` §2.5, §3.1, §5). Every value is a first
    /// guess, **INFERRED**, until Chiu has listened to a film with it — the
    /// handoff names, per number, what would settle it. The desk beatmap tool
    /// (`Tools/kamome-beatmap.py`) reads the loudness and tempo limits from this
    /// same block, so the desk and the app refuse a track by one rule.
    public struct Soundtrack: Decodable, Equatable {
        // MARK: The file the renderer writes (§3.1)

        /// Output sample rate. 48 kHz is the video world's rate; the final hit
        /// lands on the end card to within one sample of it.
        public let sampleRateHz: Double
        public let channelCount: Int
        /// AAC bitrate of the soundtrack (192 proposed in §3.1).
        public let audioBitrateKbps: Int
        /// Frames rendered per pull of the offline engine. Curves are set before
        /// each chunk and cancellation is read between chunks, so this is also
        /// the automation's time resolution (1,024 at 48 kHz ≈ 21 ms).
        public let renderChunkFrames: Int

        // MARK: What a track must measure to be used (§5)

        /// Integrated loudness every kept track is mastered to, in LUFS.
        public let targetLufs: Double
        /// How far a manifest's measured loudness may sit from the target.
        public let loudnessToleranceLu: Double
        /// The highest true peak a track may have, in dBTP. Also the ceiling
        /// any normalisation gain is held under.
        public let truePeakMaxDbtp: Double
        /// The most a track's measured tempo may drift across it, in BPM —
        /// and how far its fitted tempo may sit off the brief's. **4.5,
        /// loosened from 1.0 by Chiu 2026-11-04** (「先放寬 說不定沒差」): at 1.0,
        /// 15 of 30 ACE takes were refused for drifting 1.4–4.2 BPM and whole
        /// briefs had no track. **INFERRED** harmless: cuts sit on a fitted
        /// grid, so a drifting take may cut a little off the beat. *Settle:*
        /// Chiu listens to a film cut from a take that drifts > 3 BPM.
        public let tempoDriftMaxBpm: Double

        // MARK: How a track is fitted to a film (§2.5)

        /// A phrase, in bars: the grid a cut, a repeat and the intro offset sit on.
        public let phraseBars: Int
        /// Length of each equal-power cross-fade at a cut or a repeat, in beats.
        public let crossfadeBeats: Double
        /// Fade-in over the title card when the track starts inside its intro.
        public let fadeInS: Double
        /// Fade-out over the end card's last seconds.
        public let fadeOutS: Double

        // No dip at a stop and no lift on a photograph: the music plays straight
        // through (ADR 2026-11-03-the-music-plays-straight-through).

        // MARK: Which music (§2.3)

        /// Chiu's table (rethink A1): the style each listed country plays. A
        /// list, not a dictionary, so the style names live here and never in
        /// code — a style is location data in disguise (§4.4).
        public let countryStyles: [CountryStyle]
        /// The style every country not in the table plays (Chiu 2026-11-03,
        /// ADR 2026-11-03-the-film-chooses-its-music-and-plays-it-on-silent).
        public let unlistedStyle: String
        /// How the photographs and the film's shape choose a mood.
        public let mood: SoundtrackMoodWeights

        public struct CountryStyle: Decodable, Equatable {
            public let style: String
            /// ISO 3166-1 alpha-2, as `CLPlacemark.isoCountryCode` gives them.
            public let countries: [String]
        }

        enum CodingKeys: String, CodingKey {
            case sampleRateHz = "sample_rate_hz"
            case channelCount = "channel_count"
            case audioBitrateKbps = "audio_bitrate_kbps"
            case renderChunkFrames = "render_chunk_frames"
            case targetLufs = "target_lufs"
            case loudnessToleranceLu = "loudness_tolerance_lu"
            case truePeakMaxDbtp = "true_peak_max_dbtp"
            case tempoDriftMaxBpm = "tempo_drift_max_bpm"
            case phraseBars = "phrase_bars"
            case crossfadeBeats = "crossfade_beats"
            case fadeInS = "fade_in_s"
            case fadeOutS = "fade_out_s"
            case countryStyles = "country_styles"
            case unlistedStyle = "unlisted_style"
            case mood
        }
    }

    /// **The mood score** (§2.3 item 2). Each mood's score is its base plus
    /// the weighted signals that push toward it; the highest wins. Every
    /// weight is a first guess, **INFERRED**, until Chiu has watched films
    /// it chose. *Settle:* the picker's mood on ten real trips, judged.
    public struct SoundtrackMoodWeights: Decodable, Equatable {
        /// Starting scores. Breaks a tie with no photographs and no shape:
        /// an ordinary short film sets off bright.
        public let baseDepart: Double
        public let baseCruise: Double
        public let baseEpic: Double
        /// × the share of photographs Vision calls a landscape → epic.
        public let landscapeEpic: Double
        /// × the share of people, food and city photographs → depart.
        public let peopleDepart: Double
        /// × the share of night photographs → cruise.
        public let nightCruise: Double
        /// × how far the photographs' vividness sits above the pivot → depart.
        public let vividDepart: Double
        /// × how far it sits below the pivot → cruise.
        public let dullCruise: Double
        /// Mean of luminance and saturation (0…1) at which colour pushes
        /// neither way.
        public let vividnessPivot: Double
        /// × the warm/cool balance (−1…1), warm → depart, cool → cruise.
        public let warmthDepart: Double
        /// A photograph darker than this mean luminance counts as night.
        public let nightLuminanceMax: Double
        /// Added to epic for a film that flies to its destination.
        public let flightEpic: Double
        /// Added to epic for a film at least `longFilmS` long.
        public let longFilmEpic: Double
        public let longFilmS: Double
        /// Added to cruise for a film drawn in the dark appearance.
        public let darkCruise: Double

        enum CodingKeys: String, CodingKey {
            case baseDepart = "base_depart"
            case baseCruise = "base_cruise"
            case baseEpic = "base_epic"
            case landscapeEpic = "landscape_epic"
            case peopleDepart = "people_depart"
            case nightCruise = "night_cruise"
            case vividDepart = "vivid_depart"
            case dullCruise = "dull_cruise"
            case vividnessPivot = "vividness_pivot"
            case warmthDepart = "warmth_depart"
            case nightLuminanceMax = "night_luminance_max"
            case flightEpic = "flight_epic"
            case longFilmEpic = "long_film_epic"
            case longFilmS = "long_film_s"
            case darkCruise = "dark_cruise"
        }
    }
}
