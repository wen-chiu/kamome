import CoreLocation
@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
import XCTest

/// A recording starts only once location is allowed (ADR 2026-10-02, #190).
/// It used to start regardless: a refusal left the recording screen up with a
/// clock, no route and no word, and a drive recorded into it was lost.
///
/// These drive the real `TrackingSession` with the system prompt answered by a
/// stub. No position is involved.
final class RecordingLocationAccessTests: XCTestCase {
    private final class StubPermission: LocationPermissionProviding {
        var access: LocationAccess
        var onChange: ((LocationAccess) -> Void)?
        private(set) var requests = 0

        init(_ access: LocationAccess) { self.access = access }

        func request() { requests += 1 }

        /// The user answers the prompt, or changes the setting.
        func answer(_ access: LocationAccess) {
            self.access = access
            onChange?(access)
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-access-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func session(_ permission: StubPermission) throws -> (TrackingSession, RecordingJournalFile) {
        let config = AppConfig.loadOrDie()
        let file = RecordingJournalFile(url: directory.appendingPathComponent("journal.csv"))
        let session = TrackingSession(
            config: config.withMatching(config.matching.withBaseURL("")),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            journal: file, permission: permission
        )
        return (session, file)
    }

    func testARefusedLocationNeverStartsARecording() throws {
        let permission = StubPermission(.refused)
        let (session, journal) = try session(permission)

        session.requestStart(vehicle: .car)

        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.locationAccess, .refused, "the record sheet reads this to say why")
        XCTAssertEqual(permission.requests, 0, "iOS shows the prompt once; asking again is silent")
        XCTAssertNil(journal.read(), "a recording that never began must leave nothing for a relaunch to resume")
    }

    func testAnUnansweredPromptIsAskedBeforeAnythingStarts() throws {
        let permission = StubPermission(.undetermined)
        let (session, journal) = try session(permission)

        session.requestStart(vehicle: .scooter)

        XCTAssertEqual(permission.requests, 1)
        XCTAssertFalse(session.isRecording, "nothing records while the prompt is on screen")
        XCTAssertNil(journal.read())
    }

    func testAYesAtThePromptStartsTheRecordingThatWasAskedFor() throws {
        let permission = StubPermission(.undetermined)
        let (session, journal) = try session(permission)
        session.requestStart(vehicle: .scooter)

        permission.answer(.allowed)
        defer { session.end() }

        XCTAssertTrue(session.isRecording)
        guard case .start(_, let vehicle)? = try XCTUnwrap(journal.read()).first else {
            return XCTFail("the journal does not open with a start line")
        }
        XCTAssertEqual(vehicle, .scooter)
    }

    func testANoAtThePromptStartsNothingThenOrLater() throws {
        let permission = StubPermission(.undetermined)
        let (session, journal) = try session(permission)
        session.requestStart(vehicle: .car)

        permission.answer(.refused)
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.locationAccess, .refused)

        // Allowed afterwards in Settings: that is not Start Journey being pressed.
        permission.answer(.allowed)
        XCTAssertFalse(session.isRecording, "a trip starts when the user starts it, never by itself")
        XCTAssertNil(journal.read())
    }

    func testAnAllowedLocationStartsAtOnce() throws {
        let permission = StubPermission(.allowed)
        let (session, _) = try session(permission)

        session.requestStart(vehicle: .bicycle)
        defer { session.end() }

        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(permission.requests, 0)
    }

    /// Turned off in Settings mid-trip. The recording is kept — its track so
    /// far is the user's — and the screen is told, so it can say so.
    func testLocationRefusedMidTripIsReportedAndTheRecordingKept() throws {
        let permission = StubPermission(.allowed)
        let (session, _) = try session(permission)
        session.requestStart(vehicle: .car)
        defer { session.end() }

        permission.answer(.refused)

        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(session.locationAccess, .refused)

        permission.answer(.allowed)
        XCTAssertEqual(session.locationAccess, .allowed)
    }

    /// Built in `KamomeApp.init`, before the first frame: reading the status
    /// there is a synchronous trip to locationd that held launch on a blank
    /// screen (#235). It starts unanswered and takes the answer CoreLocation
    /// delivers right after the manager is created — which is what a Start
    /// pressed in that gap waits on, so the delivery must come by itself.
    func testThePermissionAnswersAfterLaunchWithoutAskingLocationdFirst() {
        let permission = LocationPermission()
        XCTAssertEqual(permission.access, .undetermined, "nothing is read from locationd while the app is launching")

        let answered = expectation(description: "CoreLocation delivers the current answer unprompted")
        answered.assertForOverFulfill = false
        permission.onChange = { _ in answered.fulfill() }
        wait(for: [answered], timeout: 10)

        XCTAssertEqual(permission.access, LocationAccess(CLLocationManager().authorizationStatus))
    }

    func testEveryAuthorizationStatusIsOneOfThreeAnswers() {
        XCTAssertEqual(LocationAccess(.notDetermined), .undetermined)
        XCTAssertEqual(LocationAccess(.authorizedWhenInUse), .allowed)
        XCTAssertEqual(LocationAccess(.authorizedAlways), .allowed)
        XCTAssertEqual(LocationAccess(.denied), .refused)
        // Parental controls or a profile: the user cannot allow it, and a
        // recording still cannot start.
        XCTAssertEqual(LocationAccess(.restricted), .refused)
    }
}
