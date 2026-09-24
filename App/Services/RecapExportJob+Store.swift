import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence

/// The last stage of the export: the rendered file moves into `Films/` and its
/// row is written. Split from `RecapExportJob+Render` for the file-length budget
/// when the record gained its orphan cleanup (arch review 2026-09-24); nothing
/// else about it changed in the move.
extension RecapExportJob {
    /// Moves the rendered file out of tmp and inserts its record, then resolves
    /// the stored path once. **This is what makes a completion nobody was
    /// looking at lose nothing** — the film exists before the outcome is
    /// published, so no screen has to be open for it to be kept.
    func store(
        output: RecapExporter.Output, plan: Plan, seconds: Double
    ) throws -> RecapExportOutcome {
        // The one file written: GIF when the user chose GIF, MP4 otherwise.
        guard let primaryURL = output.gifURL ?? output.videoURL else {
            return .failed(message: String(localized: "recap_failed"))
        }
        let record = try persistFilm(
            tempURL: primaryURL,
            format: output.gifURL != nil ? "gif" : "mp4",
            appearance: plan.appearance,
            durationS: plan.timeline.durationS,
            renderSeconds: seconds
        )
        guard let fileURL = FilmStore.resolvedURL(relativePath: record.relativePath) else {
            return .failed(message: String(localized: "recap_failed"))
        }
        return .finished(film: record, fileURL: fileURL)
    }

    private func persistFilm(
        tempURL: URL, format: String, appearance: RecapAppearance,
        durationS: Double, renderSeconds: Double
    ) throws -> FilmRecord {
        let relativePath = try FilmStore.moveToStore(from: tempURL)
        let fileURL = FilmStore.resolvedURL(relativePath: relativePath)
        let fileBytes = fileURL.flatMap(FilmStore.fileSize(at:))
        let record = FilmRecord(
            id: UUID().uuidString,
            tripId: request.tripId,
            relativePath: relativePath,
            format: format,
            createdAt: Date.now.timeIntervalSince1970,
            durationS: durationS,
            renderSeconds: renderSeconds,
            appearance: appearance.rawValue,
            recapMode: config.export.recapMode.rawValue,
            fileBytes: fileBytes
        )
        do {
            try repository.saveFilm(record)
        } catch {
            // The file has already left tmp, so `cleanup` cannot reach it: a
            // film with no row is a file nothing lists and nothing deletes.
            FilmStore.deleteFile(relativePath: relativePath)
            throw error
        }
        KamomeLog.recap.notice(
            "film stored: \(record.relativePath, privacy: .public) · \(fileBytes ?? 0) bytes"
        )
        return record
    }
}
