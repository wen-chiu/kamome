import AVKit
import KamomeConfig

/// **A film plays with sound on the silent switch** (Chiu 2026-11-03, ADR
/// 2026-11-03-the-film-chooses-its-music-and-plays-it-on-silent): the
/// `.playback` category, as Photos and video apps use. Until films carried
/// music nothing set a category, and the default `.soloAmbient` is muted by
/// the switch (handoff-music §4.2, VERIFIED by reading).
///
/// Playback only, which is why it lives with the players and reaches
/// `AVAudioSession` through `import AVKit` — no writer, engine or composition
/// here (`Config/architecture.json` `confined_types`). Called as a player
/// appears; setting the category twice is harmless.
enum FilmAudioSession {
    static func preparePlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            // The film still plays; only the silent switch's effect is wrong.
            KamomeLog.recap.error("film playback: the audio session category could not be set — \(error)")
        }
    }
}
