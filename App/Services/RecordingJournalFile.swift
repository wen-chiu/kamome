import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// The on-disk half of `RecordingJournal`: one append-only file next to the
/// database, open for the length of a recording.
///
/// **Durability.** Each line is handed to the kernel as it happens, without an
/// fsync: a written line survives the *process* dying — the app-switcher swipe,
/// a memory kill, an update — which is the failure this exists for. Only a
/// kernel panic could lose the last few seconds, and iOS flushes before a
/// low-battery shutdown.
///
/// **Written while the phone is locked.** A trip is recorded with the phone in
/// a pocket, so the file is protected `completeUntilFirstUserAuthentication`
/// explicitly, never `complete` — the stricter class would refuse every write
/// between screen lock and unlock.
///
/// **§0.** Real positions: the file never leaves the device — excluded from
/// backup, deleted when the trip is saved. Nothing here logs a coordinate.
final class RecordingJournalFile {
    let url: URL
    private var handle: FileHandle?

    init(url: URL) {
        self.url = url
    }

    static func defaultURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support.appendingPathComponent("recording-journal.csv")
    }

    /// Starts a fresh journal, replacing any previous one.
    func begin(_ start: RecordingJournal.Entry) {
        close()
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        guard fileManager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        ) else {
            KamomeLog.recording.error("journal: create failed — this recording is not crash-safe")
            return
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        append(start)
    }

    func append(_ entry: RecordingJournal.Entry) {
        if handle == nil { openForAppend() }
        guard let handle, let data = (RecordingJournal.line(for: entry) + "\n").data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            KamomeLog.recording.error("journal: append failed — this recording is not crash-safe")
        }
    }

    func read() -> [RecordingJournal.Entry]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return RecordingJournal.parse(text)
    }

    func remove() {
        close()
        try? FileManager.default.removeItem(at: url)
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    private func openForAppend() {
        guard let opened = try? FileHandle(forWritingTo: url) else {
            KamomeLog.recording.error("journal: open failed — this recording is not crash-safe")
            return
        }
        _ = try? opened.seekToEnd()
        handle = opened
    }
}
