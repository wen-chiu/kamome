// kamome-smoke: mirrors the Phase 0 XCTest gates as a plain executable so they
// can be demonstrated on a machine that has only Command Line Tools (no XCTest).
// CI runs the real XCTest suite; this exists for local verification only.
// Run: swift run kamome-smoke
import Foundation
import GRDB
import KamomeConfig
import KamomePersistence

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS  \(label)" : "FAIL  \(label)")
    if !condition { failures += 1 }
}

do {
    // Gate: schema v1 migration.
    let database = try AppDatabase.inMemory()
    let tables = try database.writer.read { db in
        try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    let expected: Set<String> = ["trip", "segment", "trackpoint", "stop", "photo_ref", "plan", "plan_stop"]
    check(expected.isSubset(of: tables), "schema v1 creates all 7 tables")

    // Gate: 50k trackpoint round trip < 2 s in-memory.
    let pointCount = 50_000
    try database.writer.write { db in
        try TripRecord(id: "trip-1", title: "Perf fixture", startedAt: 0, status: "completed").insert(db)
        try SegmentRecord(id: "seg-1", tripId: "trip-1", mode: "drive", startedAt: 0).insert(db)
    }
    let points = (0..<pointCount).map { index in
        TrackpointRecord(
            segmentId: "seg-1",
            ts: Double(index),
            lat: -31.95 + Double(index) * 1e-5,
            lon: 115.86 + Double(index) * 1e-5,
            hAcc: 5,
            speed: 25,
            course: 180,
            altitude: 10
        )
    }
    let start = Date()
    try database.writer.write { db in
        try TrackpointRecord.bulkInsert(points, into: db)
    }
    let fetched = try database.writer.read { db in
        try TrackpointRecord.order(sql: "ts").fetchAll(db)
    }
    let elapsed = Date().timeIntervalSince(start)
    check(fetched.count == pointCount, "read back \(fetched.count)/\(pointCount) trackpoints")
    check(elapsed < 2.0, String(format: "round trip in %.3fs (gate < 2s)", elapsed))

    // Gate: typed config loader on the shipped file.
    let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")
    let config = try TrackingConfigLoader.load(contentsOf: configURL)
    check(config.dwell.radiusM == 80, "TrackingConfig.json loads, dwell.radius_m == 80")

    // Loader fails loudly, naming the missing key. Mirrors the XCTest check
    // (drop one nested key from the shipped file) so the expectation cannot
    // drift with the config's key order.
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any] ?? [:]
    var dwell = json["dwell"] as? [String: Any] ?? [:]
    dwell.removeValue(forKey: "radius_m")
    json["dwell"] = dwell
    let broken = try JSONSerialization.data(withJSONObject: json)
    do {
        _ = try TrackingConfigLoader.load(from: broken)
        check(false, "missing key should throw")
    } catch {
        check(String(describing: error).contains("dwell.radius_m"), "missing key error names key: \(error)")
    }
} catch {
    check(false, "unexpected error: \(error)")
}

exit(failures == 0 ? 0 : 1)
