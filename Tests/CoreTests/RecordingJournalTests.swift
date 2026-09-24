import Foundation
import KamomeConfig
import KamomeTrackingEngine
import XCTest

/// A recording must survive the app being terminated (2026-09-24): the journal
/// replayed through a fresh engine has to land on exactly the state the live
/// engine held when the process died — or recovery hands back a different trip.
final class RecordingJournalTests: XCTestCase {
    private let activities: [MotionActivity?] = [
        nil,
        MotionActivity(kind: .automotive, isAtLeastMediumConfidence: true),
        MotionActivity(kind: .walking, isAtLeastMediumConfidence: false),
        MotionActivity(kind: .cycling, isAtLeastMediumConfidence: true),
        MotionActivity(kind: .stationary, isAtLeastMediumConfidence: true)
    ]

    func testEveryEntryRoundTripsExactly() {
        let entries: [RecordingJournal.Entry] = [
            .start(ts: 1_790_000_000.123456, vehicle: .scooter),
            .sample(LocationSample(ts: 1_790_000_001.5, lat: -45.031_234_567_891, lon: 168.662_1), nil),
            .sample(
                LocationSample(
                    ts: 1_790_000_002.25, lat: -45.1, lon: 168.7,
                    hAccM: 4.7, speedMps: 0.000_017, course: 359.99, altitudeM: -3.5
                ),
                MotionActivity(kind: .walking, isAtLeastMediumConfidence: false)
            ),
            .end(ts: 1_790_000_003)
        ]
        let text = entries.map(RecordingJournal.line).joined(separator: "\n")
        XCTAssertEqual(RecordingJournal.parse(text), entries)
    }

    /// A process killed mid-write leaves a partial last line; it must cost that
    /// one fix, never the journal.
    func testHalfWrittenLineIsSkippedNotFatal() {
        let good = RecordingJournal.line(for: .sample(LocationSample(ts: 10, lat: 1, lon: 2), nil))
        let text = """
        start,1,0.0,car
        \(good)
        s,11.0,1.0
        """
        let entries = RecordingJournal.parse(text)
        XCTAssertEqual(entries.count, 2)
    }

    func testUnknownFormatVersionIsNotReplayed() {
        XCTAssertNil(RecordingJournal.entry(from: "start,99,0.0,car"))
    }

    /// The load-bearing property: kill the app at any point, replay, and the
    /// engine is the one that was lost — nine days of driving, dwells included.
    func testReplayReproducesTheLiveEngineAtEveryInterruption() throws {
        let config = try GPXReplay.loadConfig()
        let points = try GPXReplay.samples(fixture: "taiwan_huandao_9days.gpx")
        let start = try XCTUnwrap(points.first).ts

        let live = TrackingEngine(config: config, vehicle: .car)
        live.start(at: start)
        var journal = [RecordingJournal.line(for: .start(ts: start, vehicle: .car))]
        var sawDwellPausedCut = false
        let cuts = Set(stride(from: 0, to: points.count, by: max(1, points.count / 12)))

        for (index, point) in points.enumerated() {
            let activity = activities[index % activities.count]
            let stateBefore = live.state
            live.process(point, activity: activity)
            journal.append(RecordingJournal.line(for: .sample(point, activity)))
            // Cut on a spread of samples, and on every dwell transition — the
            // riskiest place to die is with GPS off and a region armed.
            guard cuts.contains(index) || live.state != stateBefore else { continue }

            let recovered = try XCTUnwrap(
                RecordingJournal.replay(RecordingJournal.parse(journal.joined(separator: "\n")), config: config)
            )
            XCTAssertEqual(recovered.engine.state, live.state, "state at sample \(index)")
            XCTAssertEqual(recovered.engine.segments, live.segments, "segments at sample \(index)")
            XCTAssertEqual(recovered.engine.stops, live.stops, "stops at sample \(index)")
            XCTAssertEqual(recovered.engine.currentMode, live.currentMode, "mode at sample \(index)")
            XCTAssertEqual(recovered.samples.count, index + 1)
            XCTAssertNil(recovered.endedAt)
            if live.state == .dwellPaused { sawDwellPausedCut = true }
        }

        // Carry on after the last cut and finish both: the saved trip must match.
        let replayed = try XCTUnwrap(
            RecordingJournal.replay(RecordingJournal.parse(journal.joined(separator: "\n")), config: config)
        )
        let end = try XCTUnwrap(points.last).ts
        live.finish(at: end)
        replayed.engine.finish(at: end)
        XCTAssertEqual(replayed.engine.segments, live.segments)
        XCTAssertEqual(replayed.engine.stops, live.stops)
        XCTAssertTrue(sawDwellPausedCut, "the fixture must exercise dwells or the test proves little")
    }

    /// End Trip was pressed but the save did not complete: the journal says so,
    /// and recovery saves at that moment rather than resuming the trip.
    func testEndLineMarksTheTripAsEndedAndLaterSamplesAreIgnored() throws {
        let config = try GPXReplay.loadConfig()
        let text = [
            RecordingJournal.line(for: .start(ts: 0, vehicle: .car)),
            RecordingJournal.line(for: .sample(LocationSample(ts: 1, lat: 0, lon: 0), nil)),
            RecordingJournal.line(for: .end(ts: 5)),
            RecordingJournal.line(for: .sample(LocationSample(ts: 6, lat: 0, lon: 0.01), nil))
        ].joined(separator: "\n")
        let recovered = try XCTUnwrap(RecordingJournal.replay(RecordingJournal.parse(text), config: config))
        XCTAssertEqual(recovered.endedAt, 5)
        XCTAssertEqual(recovered.samples.count, 1)
    }

    /// A journal the app failed to delete must never leak into the next trip.
    func testOnlyTheLastRecordingIsReplayed() throws {
        let config = try GPXReplay.loadConfig()
        let text = [
            RecordingJournal.line(for: .start(ts: 0, vehicle: .car)),
            RecordingJournal.line(for: .sample(LocationSample(ts: 1, lat: 0, lon: 0), nil)),
            RecordingJournal.line(for: .start(ts: 100, vehicle: .bicycle)),
            RecordingJournal.line(for: .sample(LocationSample(ts: 101, lat: 1, lon: 1), nil))
        ].joined(separator: "\n")
        let recovered = try XCTUnwrap(RecordingJournal.replay(RecordingJournal.parse(text), config: config))
        XCTAssertEqual(recovered.startedAt, 100)
        XCTAssertEqual(recovered.engine.vehicle, .bicycle)
        XCTAssertEqual(recovered.samples.map(\.ts), [101])
    }

    func testNoStartLineMeansNoRecording() throws {
        let config = try GPXReplay.loadConfig()
        let text = RecordingJournal.line(for: .sample(LocationSample(ts: 1, lat: 0, lon: 0), nil))
        XCTAssertNil(RecordingJournal.replay(RecordingJournal.parse(text), config: config))
        XCTAssertNil(RecordingJournal.replay([], config: config))
    }

    /// Recovery runs inside a background relaunch, which iOS gives seconds, not
    /// minutes. Two weeks of recording is ~150k fixes (INFERRED from the sampling
    /// table: 50 m apart at speed, ~3 500 km of driving plus walking); this
    /// replays 200k and prints the time so the number is measured, not assumed.
    /// The bound is loose on purpose — it catches a quadratic, not a slow Mac.
    func testTwoWeeksOfJournalReplaysQuickly() throws {
        let config = try GPXReplay.loadConfig()
        var lines = [RecordingJournal.line(for: .start(ts: 0, vehicle: .car))]
        lines.reserveCapacity(200_001)
        for index in 0..<200_000 {
            // ~25 m/s eastward along -44°, with a 15-minute stop every 2 000 fixes.
            let leg = index / 2_000
            let inStop = index % 2_000 >= 1_700
            let moving = leg * 1_700 + min(index % 2_000, 1_700)
            let sample = LocationSample(
                ts: Double(index) * 3,
                lat: -44.0,
                lon: 168.0 + Double(moving) * 0.001,
                hAccM: 5,
                speedMps: inStop ? 0 : 25
            )
            lines.append(RecordingJournal.line(for: .sample(sample, nil)))
        }
        let text = lines.joined(separator: "\n")

        let clock = ContinuousClock()
        var recovered: RecordingJournal.Recovered?
        let elapsed = clock.measure {
            recovered = RecordingJournal.replay(RecordingJournal.parse(text), config: config)
        }
        print("RECORDING_JOURNAL_REPLAY 200000 samples, \(text.utf8.count / 1_000_000) MB: \(elapsed)")
        XCTAssertEqual(recovered?.samples.count, 200_000)
        XCTAssertLessThan(elapsed, .seconds(30))
    }
}
