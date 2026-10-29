import CoreMotion
@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
import XCTest

/// Answers the Motion & Fitness prompt for a test, as `StubPermission` answers
/// the location prompt in `RecordingLocationAccessTests`.
final class StubMotionPermission: MotionPermissionProviding {
    private(set) var needsAsking: Bool
    private(set) var asks = 0
    private var answered: (() -> Void)?

    init(answered: Bool) { needsAsking = !answered }

    func ask(answered: @escaping () -> Void) {
        asks += 1
        self.answered = answered
    }

    /// The user taps Allow or Don't Allow; the recording does not care which.
    func answer() {
        needsAsking = false
        answered?()
        answered = nil
    }

    /// Answered without the handler being called back.
    func answerSilently() { needsAsking = false }
}

/// Motion & Fitness is asked while a recording is starting, never after it has
/// ended (Chiu 2026-10-29, ADR 2026-10-29, #196). On the simulator the prompt
/// used to come up on Home after End Trip, raised by `stopActivityUpdates`.
///
/// `isRecording` is what raises the recording screen and, with it, Kamome's
/// "Keep recording with the screen off" card. So "asked while it is still
/// false" is "asked on the record sheet, before the card". These drive the
/// real `TrackingSession` with both prompts answered by stubs. No position is
/// involved.
final class RecordingMotionPromptTests: XCTestCase {
    private final class StubLocation: LocationPermissionProviding {
        var access: LocationAccess
        var onChange: ((LocationAccess) -> Void)?
        private(set) var requests = 0

        init(_ access: LocationAccess) { self.access = access }

        func request() { requests += 1 }

        func answer(_ access: LocationAccess) {
            self.access = access
            onChange?(access)
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-motion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func session(
        _ location: StubLocation, _ motion: StubMotionPermission
    ) throws -> (TrackingSession, RecordingJournalFile) {
        let config = AppConfig.loadOrDie()
        let file = RecordingJournalFile(url: directory.appendingPathComponent("journal.csv"))
        let session = TrackingSession(
            config: config.withMatching(config.matching.withBaseURL("")),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            journal: file, permission: location, motion: motion
        )
        return (session, file)
    }

    func testAnUnansweredMotionPromptIsAskedBeforeTheRecordingScreen() throws {
        let motion = StubMotionPermission(answered: false)
        let (session, journal) = try session(StubLocation(.allowed), motion)

        session.requestStart(vehicle: .car)

        XCTAssertEqual(motion.asks, 1, "Start Journey asks for Motion & Fitness")
        XCTAssertFalse(session.isRecording, "the recording screen, and Kamome's card with it, waits for the answer")
        XCTAssertNil(journal.read(), "nothing records while the prompt is on screen")
    }

    func testEitherAnswerStartsTheRecordingThatWasAskedFor() throws {
        let motion = StubMotionPermission(answered: false)
        let (session, journal) = try session(StubLocation(.allowed), motion)
        session.requestStart(vehicle: .bicycle)

        motion.answer()
        defer { session.end() }

        XCTAssertTrue(session.isRecording, "a refusal records on GPS alone; it never stops the recording")
        guard case .start(_, let vehicle)? = try XCTUnwrap(journal.read()).first else {
            return XCTFail("the journal does not open with a start line")
        }
        XCTAssertEqual(vehicle, .bicycle)
    }

    /// The whole first recording, in order: location, then motion, then the
    /// recording screen.
    func testMotionIsAskedOnlyOnceLocationIsAllowed() throws {
        let location = StubLocation(.undetermined)
        let motion = StubMotionPermission(answered: false)
        let (session, _) = try session(location, motion)

        session.requestStart(vehicle: .scooter)
        XCTAssertEqual(location.requests, 1)
        XCTAssertEqual(motion.asks, 0, "two system prompts are never raised at once")

        location.answer(.allowed)
        XCTAssertEqual(motion.asks, 1, "asked as soon as location is allowed")
        XCTAssertFalse(session.isRecording)

        motion.answer()
        defer { session.end() }
        XCTAssertTrue(session.isRecording)
    }

    func testARefusedLocationNeverAsksForMotion() throws {
        let refusedUpFront = StubMotionPermission(answered: false)
        let (first, _) = try session(StubLocation(.refused), refusedUpFront)
        first.requestStart(vehicle: .car)
        XCTAssertEqual(refusedUpFront.asks, 0, "no recording starts, so there is nothing to ask for")

        let location = StubLocation(.undetermined)
        let refusedAtPrompt = StubMotionPermission(answered: false)
        let (second, _) = try session(location, refusedAtPrompt)
        second.requestStart(vehicle: .car)
        location.answer(.refused)
        XCTAssertEqual(refusedAtPrompt.asks, 0)
        XCTAssertFalse(second.isRecording)
    }

    /// Everyone who has answered before: nothing changes for them.
    func testAnAnsweredPromptIsNeverAskedAgain() throws {
        let motion = StubMotionPermission(answered: true)
        let (session, _) = try session(StubLocation(.allowed), motion)

        session.requestStart(vehicle: .car)
        defer { session.end() }

        XCTAssertEqual(motion.asks, 0)
        XCTAssertTrue(session.isRecording, "the recording starts at once, as before")
    }

    func testAPressWhileThePromptIsUpDoesNotAskTwice() throws {
        let motion = StubMotionPermission(answered: false)
        let (session, _) = try session(StubLocation(.allowed), motion)

        session.requestStart(vehicle: .car)
        session.requestStart(vehicle: .car)

        XCTAssertEqual(motion.asks, 1)
        XCTAssertFalse(session.isRecording)
    }

    /// If the answer is given but never called back (UNKNOWN whether a phone
    /// can do that), Start Journey is not stuck: pressed again, it starts.
    func testStartJourneyStartsOnceThePromptIsAnsweredEvenIfNoCallComes() throws {
        let motion = StubMotionPermission(answered: false)
        let (session, _) = try session(StubLocation(.allowed), motion)
        session.requestStart(vehicle: .car)

        motion.answerSilently()
        session.requestStart(vehicle: .car)
        defer { session.end() }

        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(motion.asks, 1)
    }

    /// The recording reads motion only on an answered yes. It never raises the
    /// prompt itself: unanswered at that point means a recording resumed after
    /// a relaunch, with no one to ask. The simulator has no activity at all.
    func testARecordingReadsMotionOnlyOnAYes() {
        XCTAssertTrue(LocationService.readsMotionActivity(available: true, authorization: .authorized))
        XCTAssertFalse(LocationService.readsMotionActivity(available: true, authorization: .notDetermined),
                       "a recording must not raise the prompt over the recording screen")
        XCTAssertFalse(LocationService.readsMotionActivity(available: true, authorization: .denied))
        XCTAssertFalse(LocationService.readsMotionActivity(available: true, authorization: .restricted))
        XCTAssertFalse(LocationService.readsMotionActivity(available: false, authorization: .authorized),
                       "the simulator: nothing to read")
    }
}
