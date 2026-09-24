import KamomeConfig
import XCTest

/// **`export.pipeline` is read from the shipped file and survives every copy**
/// (arch review 2026-09-24, P1-9/P1-10). The copy helpers rebuild `Export`
/// through its initialiser, where `pipeline` has a default for hand-built test
/// configs — so a helper that forgot to pass it would silently reset the
/// shipped budget to that default. This is the test that would notice.
final class ExportPipelineConfigTests: XCTestCase {
    private let shippedURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")

    private func shipped() throws -> TrackingConfig.Export {
        try TrackingConfigLoader.load(contentsOf: shippedURL).export
    }

    func testThePipelineComesFromTheShippedFile() throws {
        let pipeline = try shipped().pipeline
        XCTAssertGreaterThan(pipeline.prefetchDepth, 0)
        XCTAssertGreaterThan(pipeline.compositeConcurrency, 0)
        XCTAssertGreaterThan(pipeline.snapshotTimeoutS, 0)
    }

    func testEveryCopyKeepsThePipeline() throws {
        // The shipped values equal `.handBuilt`, so a reset would not show on
        // them: load a copy of the file whose pipeline no default could produce.
        let base = try shipped(pipeline: ["prefetch_depth": 3, "composite_concurrency": 2, "snapshot_timeout_s": 7])
        XCTAssertNotEqual(base.pipeline, .handBuilt, "precondition: the marked pipeline differs from the default")
        let copies: [TrackingConfig.Export] = [
            base.withFollowHeadingUp(!base.followHeadingUp),
            base.withAllocationZeroShare(base.allocationZeroShare),
            base.withRecapMode(base.recapMode),
            base.withTotalDuration(min: base.totalDurationMinS, max: base.totalDurationMaxS),
            base.withCrossingBeatS(base.crossingBeatS),
            base.withKeyframeIntervalFrames(base.keyframeIntervalFrames),
            base.withSnapshotStations(
                maxMagnification: base.snapshotStationMaxMagnification, padding: base.snapshotStationPadding
            )
        ]
        for copy in copies {
            XCTAssertEqual(copy.pipeline, base.pipeline)
        }
    }

    private func shipped(pipeline: [String: Any]) throws -> TrackingConfig.Export {
        let data = try Data(contentsOf: shippedURL)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var export = try XCTUnwrap(root["export"] as? [String: Any])
        export["pipeline"] = pipeline
        root["export"] = export
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        return try TrackingConfigLoader.load(contentsOf: url).export
    }
}
