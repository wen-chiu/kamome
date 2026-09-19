@testable import Kamome
import Photos
import UIKit
import XCTest

/// The iCloud download phase (Chiu 2026-09-19). PhotoKit itself cannot be
/// driven from a test — no library, no iCloud — so what is held here is
/// everything *around* the call: how a callback is classified, that a request
/// ends exactly once however cancel and completion race, that a cancelled warm
/// stops asking, and that progress reaches the screen without leaking into the
/// next film. What PhotoKit does with the request is a device question
/// (`HANDOFF.md`).
final class PhotoPreloadTests: XCTestCase {
    private let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }

    // MARK: - Classifying a PhotoKit callback

    func testALocalImageIsLoadedWhateverTheNetworkSetting() {
        for allowNetwork in [false, true] {
            guard case .loaded = PhotoKitImageLoader.outcome(image: image, info: nil, allowNetwork: allowNetwork) else {
                return XCTFail("an image PhotoKit returned is loaded (allowNetwork: \(allowNetwork))")
            }
        }
    }

    /// The flag is what separates "download these" from "these are gone".
    func testAnInCloudPhotoIsReportedRatherThanFailedWhenNetworkIsNotAllowed() {
        let info: [AnyHashable: Any] = [PHImageResultIsInCloudKey: NSNumber(value: true)]
        guard case .inCloud = PhotoKitImageLoader.outcome(image: nil, info: info, allowNetwork: false) else {
            return XCTFail("iCloud-only and not allowed to fetch it → .inCloud, the download queue")
        }
    }

    /// A request that *was* allowed to download and still has no image has
    /// failed. Reporting `.inCloud` here would queue it for another download.
    func testARequestThatMayDownloadNeverReportsInCloud() {
        let info: [AnyHashable: Any] = [PHImageResultIsInCloudKey: NSNumber(value: true)]
        guard case .failed = PhotoKitImageLoader.outcome(image: nil, info: info, allowNetwork: true) else {
            return XCTFail("a failed download is .failed, not another trip round the queue")
        }
    }

    func testAMissingImageWithNoCauseIsAFailureAndCancellationIsNotOne() {
        guard case .failed = PhotoKitImageLoader.outcome(image: nil, info: nil, allowNetwork: false) else {
            return XCTFail("no image, no reason → failed")
        }
        let cancelled: [AnyHashable: Any] = [PHImageCancelledKey: NSNumber(value: true)]
        guard case .cancelled = PhotoKitImageLoader.outcome(image: nil, info: cancelled, allowNetwork: true) else {
            return XCTFail("a cancelled request is cancelled, so it is not counted as a failed download")
        }
    }

    // MARK: - A request ends exactly once

    private func outcome(
        _ script: @escaping (PendingRequest) -> Void
    ) async -> PhotoFetch {
        let pending = PendingRequest()
        return await withCheckedContinuation { continuation in
            guard pending.install(continuation) else { return }
            script(pending)
        }
    }

    func testTheFirstCompletionWinsAndALateCancelDoesNothing() async {
        let result = await outcome { pending in
            pending.finish(.failed, stopRequest: false)
            pending.finish(.inCloud, stopRequest: false)
            pending.cancel()
        }
        guard case .failed = result else { return XCTFail("the first answer stands") }
    }

    func testCancellingResumesTheCallerEvenIfPhotoKitNeverCallsBack() async {
        let result = await outcome { $0.cancel() }
        guard case .cancelled = result else { return XCTFail("cancel must not wait for Photos to answer") }
    }

    /// The task can be cancelled before the request has been made at all.
    func testCancellingBeforeTheRequestIsMadeNeverIssuesOne() async {
        let pending = PendingRequest()
        pending.cancel()
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<PhotoFetch, Never>) in
            XCTAssertFalse(pending.install(continuation), "an already-cancelled request must not be issued")
        }
        guard case .cancelled = result else { return XCTFail("resumed as cancelled") }
    }

    // MARK: - Warming

    /// A cancelled export must not carry on asking PhotoKit for photos.
    func testAWarmThatIsToldToStopResolvesNothing() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kamome-preload-\(UUID()).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = PhotoLibraryPhotoResolver()
        let summary = await resolver.warm([.file(url)], targetPx: 100, timeoutS: 1, shouldContinue: { false })
        XCTAssertEqual(summary.resolved, 0)
        XCTAssertNil(resolver.image(for: .file(url), targetPx: 100))

        let unhindered = await resolver.warm([.file(url)], targetPx: 100, timeoutS: 1)
        XCTAssertEqual(unhindered.resolved, 1, "the same photo loads when nobody has cancelled")
        XCTAssertEqual(unhindered.downloaded, 0, "a file on this device is never a download")
    }

    // MARK: - The screen

    @MainActor
    func testPreloadProgressReachesTheScreenAndCannotLeakIntoTheNextRun() async {
        let coordinator = RecapExportCoordinator()
        let request = RecapExportRequest(tripId: "trip-a", photosEnabled: true, format: .mp4, appearance: .dark)
        let job = SpyExportJob()
        coordinator.start(request: request, job: job)
        for _ in 0..<10_000 where !job.hasStarted { await Task.yield() }

        let progress = PhotoLibraryPhotoResolver.PreloadProgress(completed: 12, total: 38, fraction: 12.0 / 38.0)
        job.report(preload: progress)
        XCTAssertEqual(coordinator.running?.photoPreload, progress)
        job.report(preload: nil)
        XCTAssertNil(coordinator.running?.photoPreload, "nil ends the phase, so the render bar takes over")

        coordinator.cancel(tripId: "trip-a")
        job.complete(.cancelled)
        for _ in 0..<10_000 where coordinator.running != nil { await Task.yield() }
        job.report(preload: progress) // a stale run's late update
        XCTAssertNil(coordinator.running, "nothing is running, so nothing shows a download")
    }
}
