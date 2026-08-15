@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeImportKit
import XCTest

/// **What the earned-stops rule does to trips it was never fitted to.**
///
/// The rule's four numbers were reverse-derived from three trips — Miyakojima,
/// New Zealand, Iceland — and reproduce them exactly. That is not evidence; it is
/// the definition of a fit. `body_span_padding` was fitted to Iceland and gave New
/// Zealand 4.14x. `tier_skip_share` needed 0.82 for Iceland and 0.5 for New
/// Zealand and was deleted for it. **Both shipped after being validated only on
/// the trips they came from.**
///
/// So this report is the acceptance condition, decided in advance (Chiu
/// 2026-08-14): print what the rule gives for the small committed fixtures it was
/// never fitted to, and for trip sizes far outside the fitted range, before any of
/// it is judged.
///
///     TEST_RUNNER_KAMOME_DURATION_RULE_REPORT=1 \
///     xcodebuild -scheme Kamome test -destination '…' \
///       -only-testing:KamomeTests/RecapDurationRuleReportTests
///
/// ⚠️ It reports **stop counts and seconds only** — never a coordinate, never a
/// place name (CLAUDE.md §0). A local dump shadowing a committed fixture is named
/// as such by `tripFixture`, so a reader can tell whether a row describes a real
/// trip or the synthetic placeholder.
final class RecapDurationRuleReportTests: XCTestCase {
    private static let fixtures = [
        "margaret-river", "finland", "miyakojima", "new-zealand", "nz-real", "iceland"
    ]

    func testReportWhatTheRuleGivesTripsItWasNotFittedTo() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_DURATION_RULE_REPORT"] == "1",
            "Generalization report — set KAMOME_DURATION_RULE_REPORT=1."
        )
        let full = try AppConfig.loadOrDie()
        let config = full.export
        let clustering = ImportClusteringConfig(
            stopRadiusM: full.photoImport.stopRadiusM,
            stopSplitGapS: full.photoImport.stopSplitGapS,
            minPhotosPerStop: full.photoImport.minPhotosPerStop
        )

        var lines: [String] = [
            "KAMOME_DURATION_RULE floor \(config.earnedStopsFloor) · cap \(config.earnedStopsCap) · "
                + "+\(config.earnedStopsPerDoubling)/doubling from \(config.earnedStopsReferenceTripStops) stops · "
                + String(format: "cost %.2f s dwell/stop", StopPhotoAllocator.presentationCostS(config: config)),
            "  fixture            trip stops   earned   film      was    bound by"
        ]

        for name in Self.fixtures {
            // The real clusterer, so a row is what the app would actually build —
            // not an assumed stop count.
            let trip = try RecapDemoFilmTests.tripFixture(named: name)
            let plan = PhotoImportClusterer.plan(photos: trip.photos, config: clustering)
            let tripStops = plan.stops.count
            let earned = min(StopPhotoAllocator.earnedStopCount(tripStopCount: tripStops, config: config), tripStops)
            let film = max(StopPhotoAllocator.earnedDurationS(presentedStops: earned, config: config),
                           config.totalDurationMinS)
            lines.append(String(
                format: "  %-18@ %10d %8d %7.1fs %7.1fs    %@",
                name as NSString, tripStops, earned, film, config.totalDurationMaxS,
                Self.boundName(tripStops: tripStops, earned: earned, film: film, config: config) as NSString
            ))
        }

        lines.append("  — synthetic sweep, well outside the three fitted trips —")
        for tripStops in [1, 2, 3, 5, 10, 15, 20, 30, 36, 40, 65, 120, 500, 5_000] {
            let earned = min(StopPhotoAllocator.earnedStopCount(tripStopCount: tripStops, config: config), tripStops)
            let film = max(StopPhotoAllocator.earnedDurationS(presentedStops: earned, config: config),
                           config.totalDurationMinS)
            lines.append(String(
                format: "  %-18@ %10d %8d %7.1fs %7.1fs    %@",
                "(synthetic)" as NSString, tripStops, earned, film, config.totalDurationMaxS,
                Self.boundName(tripStops: tripStops, earned: earned, film: film, config: config) as NSString
            ))
        }
        print(lines.joined(separator: "\n"))

        // The report is the deliverable, but two properties are asserted so this
        // cannot quietly start printing nonsense: never more stops than the trip
        // has, and never past the cap.
        for tripStops in [0, 1, 3, 10, 65, 5_000] {
            let earned = min(StopPhotoAllocator.earnedStopCount(tripStopCount: tripStops, config: config), tripStops)
            XCTAssertLessThanOrEqual(earned, tripStops, "\(tripStops) stops")
            XCTAssertLessThanOrEqual(earned, config.earnedStopsCap, "\(tripStops) stops")
        }
    }

    /// Which constraint decided this row — the honest way to read a fitted rule is
    /// to know which of its numbers is actually doing the work on each trip.
    private static func boundName(
        tripStops: Int, earned: Int, film: Double, config: TrackingConfig.Export
    ) -> String {
        if film <= config.totalDurationMinS { return "duration floor" }
        if earned == tripStops { return "the trip itself" }
        if earned >= config.earnedStopsCap { return "stop cap" }
        if earned <= config.earnedStopsFloor { return "stop floor" }
        return "the curve"
    }
}
