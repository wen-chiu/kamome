@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
import XCTest

/// A recording survives the app being terminated (2026-09-24). These drive the
/// real `TrackingSession` against a journal on disk, the way a relaunch finds it.
///
/// Positions are synthetic and routing is switched off, so nothing here reaches
/// the network with a leg to match.
final class RecordingRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func offlineConfig() -> TrackingConfig {
        let config = AppConfig.loadOrDie()
        return config.withMatching(config.matching.withBaseURL(""))
    }

    /// Ten minutes of driving at 20 m/s, one fix every 5 s.
    private func drive(from startTs: Double) -> [LocationSample] {
        (1...120).map { index in
            LocationSample(
                ts: startTs + Double(index) * 5,
                lat: -44.0,
                lon: 168.0 + Double(index) * 0.00125,
                hAccM: 5,
                speedMps: 20
            )
        }
    }

    private func writeJournal(_ entries: [RecordingJournal.Entry], to file: RecordingJournalFile) {
        guard let first = entries.first else { return }
        file.begin(first)
        for entry in entries.dropFirst() { file.append(entry) }
        file.close()
    }

    func testAnUnendedJournalIsResumedOnLaunch() throws {
        let file = RecordingJournalFile(url: directory.appendingPathComponent("journal.csv"))
        let samples = drive(from: 1_000)
        writeJournal([.start(ts: 1_000, vehicle: .car)] + samples.map { .sample($0, nil) }, to: file)
        let lastFix = try XCTUnwrap(samples.last).ts

        let repository = TripRepository(database: try AppDatabase.inMemory())
        let session = TrackingSession(
            config: offlineConfig(), repository: repository, journal: file,
            now: Date(timeIntervalSince1970: lastFix + 1_800)
        )

        XCTAssertTrue(session.isRecording, "a recording nobody ended must carry on")
        XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(session.traveledPath.count, samples.count)
        XCTAssertGreaterThan(session.distanceM, 10_000)
        XCTAssertEqual(session.interruption, TrackingSession.Interruption(gapS: 1_800))
        XCTAssertTrue(session.trips.isEmpty, "nothing is saved until the trip ends")

        // Ending the recovered recording saves the whole trip and clears the journal.
        session.end(now: Date(timeIntervalSince1970: lastFix + 1_900))
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.trips.count, 1)
        XCTAssertEqual(session.trips.first?.startedAt, 1_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    /// End Trip was pressed, the save never completed: saved as it ended, not resumed.
    func testAnEndedJournalIsSavedNotResumed() throws {
        let file = RecordingJournalFile(url: directory.appendingPathComponent("journal.csv"))
        let samples = drive(from: 1_000)
        let endTs = try XCTUnwrap(samples.last).ts + 10
        writeJournal(
            [.start(ts: 1_000, vehicle: .car)] + samples.map { .sample($0, nil) } + [.end(ts: endTs)],
            to: file
        )

        let repository = TripRepository(database: try AppDatabase.inMemory())
        let session = TrackingSession(config: offlineConfig(), repository: repository, journal: file)

        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.trips.count, 1)
        XCTAssertEqual(session.trips.first?.endedAt, endTs)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testNoJournalMeansNoRecording() throws {
        let file = RecordingJournalFile(url: directory.appendingPathComponent("journal.csv"))
        let session = TrackingSession(
            config: offlineConfig(), repository: TripRepository(database: try AppDatabase.inMemory()), journal: file
        )
        XCTAssertFalse(session.isRecording)
        XCTAssertNil(session.interruption)
    }

    /// Every fix a live recording receives is on disk before the engine sees it.
    func testALiveRecordingWritesItsJournal() throws {
        let file = RecordingJournalFile(url: directory.appendingPathComponent("journal.csv"))
        let session = TrackingSession(
            config: offlineConfig(), repository: TripRepository(database: try AppDatabase.inMemory()), journal: file
        )
        session.start(vehicle: .scooter, now: Date(timeIntervalSince1970: 5_000))
        defer { session.end() }

        let entries = try XCTUnwrap(file.read())
        XCTAssertEqual(entries, [.start(ts: 5_000, vehicle: .scooter)])
    }
}
