import KamomeExportEngine
import SwiftUI

/// **「音樂」 on the film sheet** (`Docs/handoff-music-in-the-film.md` §4.2):
/// 自動 or 無音樂, nothing more before the film exists — a person cannot
/// choose music for a film they have not seen, so the choosing is the
/// player's 「換音樂」. 自動 is the default (ADR
/// 2026-11-03-the-film-chooses-its-music-and-plays-it-on-silent).
struct FilmMusicRow: View {
    @Bindable var model: RecapModel

    var body: some View {
        Picker("recap_music_header", selection: $model.music) {
            Text("recap_music_auto").tag(FilmMusicChoice.auto)
            Text("recap_music_none").tag(FilmMusicChoice.none)
        }
        .pickerStyle(.menu)
    }
}

/// **The music could not be added** (§4.1): said on the finished screen, with
/// 「再試一次」, which redoes only the music and the mux. The film is already
/// kept, so this is a fact and an offer, never an error (UX rule 5).
struct RecapMusicFailedNotice: View {
    let model: RecapModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("recap_music_failed", systemImage: "music.note")
                .font(.footnote)
                .foregroundStyle(Color(.warningText))
            if model.isRetryingMusic {
                ProgressView { Text("recap_music_retrying").font(.footnote) }
            } else {
                Button("recap_music_retry") { Task { await model.retryMusic() } }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// Words for a mood — never a region (§4.4: a screenshot is shared).
extension SoundtrackMood {
    var label: LocalizedStringKey {
        switch self {
        case .depart: return "music_mood_depart"
        case .cruise: return "music_mood_cruise"
        case .epic: return "music_mood_epic"
        }
    }
}
