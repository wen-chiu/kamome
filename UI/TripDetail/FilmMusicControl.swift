import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import Observation
import SwiftUI

/// **「換音樂」's state for one film** (`Docs/handoff-music-in-the-film.md`
/// §4.2): which option is playing, the preview file while one is on trial, and
/// what the player should be showing. Choosing renders the music beside the
/// film's picture into a temporary file, which the player plays; 「使用這首」
/// moves it into place; closing throws it away (`FilmMusicChange`).
@Observable
@MainActor
final class FilmMusicEditor {
    private(set) var film: FilmRecord
    /// The option on trial, while its preview exists.
    private(set) var trial: FilmMusicChange.Option?
    private var previewURL: URL?
    private(set) var isPreparing = false
    private(set) var failed = false
    /// Bumped whenever the file the player should show changes.
    private(set) var revision = 0

    private let config: TrackingConfig
    private let repository: TripRepository

    init(film: FilmRecord, config: TrackingConfig, repository: TripRepository) {
        self.film = film
        self.config = config
        self.repository = repository
    }

    /// nil for a film made before music: it has no cue sheet to cut to.
    var options: [FilmMusicChange.Option]? {
        FilmMusicChange.options(for: film, catalog: SoundtrackCatalog.bundled(limits: config.soundtrack))
    }

    /// What the player plays: the preview on trial, else the film.
    var playbackURL: URL? {
        previewURL ?? FilmStore.resolvedURL(relativePath: film.relativePath)
    }

    /// The option the list marks: the one on trial, else the film's own.
    func isSelected(_ option: FilmMusicChange.Option) -> Bool {
        trial.map { $0.id == option.id } ?? option.isCurrent
    }

    func choose(_ option: FilmMusicChange.Option) async {
        guard !isPreparing else { return }
        failed = false
        if option.isCurrent {
            discard()
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let url = try await FilmMusicChange.preview(film: film, trackId: option.trackId, config: config)
            FilmMusicChange.discard(preview: previewURL)
            previewURL = url
            trial = option
        } catch {
            KamomeLog.recap.error("music: a preview failed — \(RecapExportJob.failureCode(error), privacy: .public)")
            failed = true
        }
        revision += 1
    }

    /// 「使用這首」. Returns the updated record for the screen behind.
    func use() -> FilmRecord? {
        guard let previewURL, let trial else { return nil }
        do {
            let updated = try FilmMusicChange.use(
                preview: previewURL, film: film, trackId: trial.trackId, repository: repository
            )
            self.previewURL = nil
            self.trial = nil
            if let updated { film = updated }
            revision += 1
            return updated
        } catch {
            let code = RecapExportJob.failureCode(error)
            KamomeLog.recap.error("music: the new music could not replace the film's — \(code, privacy: .public)")
            failed = true
            return nil
        }
    }

    /// Back to the film as stored; the preview is thrown away.
    func discard() {
        guard previewURL != nil else { return }
        FilmMusicChange.discard(preview: previewURL)
        previewURL = nil
        trial = nil
        revision += 1
    }
}

/// The 「換音樂」 menu and, while a choice is on trial, 「使用這首」.
struct FilmMusicControl: View {
    let editor: FilmMusicEditor
    let onUse: (FilmRecord) -> Void

    var body: some View {
        if let options = editor.options {
            VStack(spacing: 8) {
                HStack {
                    Menu {
                        ForEach(options) { option in
                            Button {
                                Task { await editor.choose(option) }
                            } label: {
                                if editor.isSelected(option) {
                                    Label { label(option) } icon: { Image(systemName: "checkmark") }
                                } else {
                                    label(option)
                                }
                            }
                        }
                    } label: {
                        Label("film_music_change", systemImage: "music.note")
                    }
                    .disabled(editor.isPreparing)
                    if editor.trial != nil {
                        Spacer()
                        Button("film_music_use") {
                            if let updated = editor.use() { onUse(updated) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                if editor.isPreparing {
                    ProgressView { Text("film_music_preparing").font(.footnote) }
                } else if editor.failed {
                    Text("film_music_failed")
                        .font(.footnote)
                        .foregroundStyle(Color(.warningText))
                }
            }
        }
    }

    /// The mood in words; a second take of the same mood is numbered.
    private func label(_ option: FilmMusicChange.Option) -> Text {
        guard let mood = option.mood else { return Text("recap_music_none") }
        return option.take > 1 ? Text(mood.label) + Text(verbatim: " \(option.take)") : Text(mood.label)
    }
}
