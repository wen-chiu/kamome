@testable import Kamome
import KamomeExportEngine
import XCTest

/// The shortfall report is the whole point of the iCloud work (Chiu 2026-08-02):
/// the failure it names is silent, so what matters is that a partial load is
/// *counted* rather than quietly producing blank cards.
final class PhotoShortfallTests: XCTestCase {
    func testWarmSummaryCountsWhatItCouldNotLoad() {
        let summary = PhotoLibraryPhotoResolver.WarmSummary(requested: 47, resolved: 9, inCloud: 36)
        XCTAssertEqual(summary.missing, 38, "38 cards will render blank")
        XCTAssertEqual(summary.inCloud, 36, "and 36 of those are fixable by downloading them")
    }

    /// A fully-resolved warm must not raise the notice — the banner has to mean
    /// something when it appears.
    func testNoShortfallWhenEverythingResolves() {
        XCTAssertEqual(
            PhotoLibraryPhotoResolver.WarmSummary(requested: 12, resolved: 12, inCloud: 0).missing, 0
        )
    }

    /// File-backed refs never report an iCloud cause — only PhotoKit assets can.
    func testFileRefsResolveWithoutPhotoKit() async {
        let resolver = PhotoLibraryPhotoResolver()
        let url = URL(fileURLWithPath: "/nonexistent/missing.jpg")
        let summary = await resolver.warm([.file(url)], targetPx: 100)
        XCTAssertEqual(summary.inCloud, 0, "a missing file is not an iCloud problem")
    }
}
