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
        /// The most a track's measured tempo may drift across it, in BPM.
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

        // MARK: Moments the music answers (§2.5 item 5)

        /// Gain while a stop's photographs play, in dB (negative: a dip).
        public let stopDipDb: Double
        /// Low-pass cutoff while a stop's photographs play.
        public let stopCutoffHz: Double
        /// The cutoff that means "no filter": where the curve rests.
        public let openCutoffHz: Double
        /// How long the dip takes to settle, in beats.
        public let dipRampBeats: Double
        /// The shortest return to full level after the car sets off, in beats;
        /// the return lands on the first downbeat at least this far after `go`.
        public let returnMinRampBeats: Double
        /// An accent moves onto the nearest beat only within this; farther, it
        /// plays on the cue itself (§2.5 item 6).
        public let accentSnapToleranceS: Double
        /// Whether a photograph changing opens the filter a step.
        public let photoAccentEnabled: Bool
        /// How far the cutoff opens on a photograph change, as a multiple of the
        /// dip's cutoff.
        public let photoAccentCutoffRatio: Double
        /// How fast it opens.
        public let photoAccentAttackS: Double
        /// How long it takes to settle back, in beats.
        public let photoAccentDecayBeats: Double

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
            case stopDipDb = "stop_dip_db"
            case stopCutoffHz = "stop_cutoff_hz"
            case openCutoffHz = "open_cutoff_hz"
            case dipRampBeats = "dip_ramp_beats"
            case returnMinRampBeats = "return_min_ramp_beats"
            case accentSnapToleranceS = "accent_snap_tolerance_s"
            case photoAccentEnabled = "photo_accent_enabled"
            case photoAccentCutoffRatio = "photo_accent_cutoff_ratio"
            case photoAccentAttackS = "photo_accent_attack_s"
            case photoAccentDecayBeats = "photo_accent_decay_beats"
        }
    }
}
