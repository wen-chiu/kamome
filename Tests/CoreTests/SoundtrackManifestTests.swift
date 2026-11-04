import KamomeConfig
import KamomeExportEngine
import XCTest

/// **One schema, two validators, one set of fixtures** (`Docs/handoff-music-in-the-film.md`
/// §2.2, §5). The desk tool writes manifests in Python; the app decodes them in
/// Swift. `Scripts/check-soundtrack-manifests.sh` holds the Python validator to
/// these same files, so if either side's rules drift, one of the two fails.
final class SoundtrackManifestTests: XCTestCase {
    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The cross-check: a manifest `Tools/kamome-beatmap.py` produced from a real
    /// track (committed without its audio) decodes and validates here.
    func testTheDeskToolsManifestDecodesAndValidates() throws {
        let url = SoundtrackTestSupport.fixtures.appendingPathComponent("anthem-depart-s1855554642.json")
        let manifest = try SoundtrackManifest.load(from: Data(contentsOf: url), limits: SoundtrackTestSupport.soundtrack())
        XCTAssertEqual(manifest.id, "anthem-depart-s1855554642")
        XCTAssertEqual(manifest.bpm, 120, accuracy: 1, "the brief's tempo")
        XCTAssertEqual(manifest.sections.last?.role, .outro)
        XCTAssertFalse(manifest.sectionsConfirmed, "proposed by the tool; Chiu has not signed these")
        // And it can be arranged to a film, end to end.
        let plan = try SoundtrackArrangement.plan(
            manifest: manifest, cues: SoundtrackTestSupport.cues(durationS: 90), durationS: 90,
            config: SoundtrackTestSupport.soundtrack()
        )
        XCTAssertEqual(plan.finalHitS, 87)
    }

    func testEveryInvalidFixtureIsRefusedWithItsCode() throws {
        let directory = SoundtrackTestSupport.fixtures.appendingPathComponent("invalid")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 15, "one fixture per refusal")
        let limits = try SoundtrackTestSupport.soundtrack()
        for url in files {
            let expected = try XCTUnwrap(json(url)["_expect"] as? String, url.lastPathComponent)
            let data = try Data(contentsOf: url)
            if expected == "decode" {
                XCTAssertThrowsError(try JSONDecoder().decode(SoundtrackManifest.self, from: data)) { error in
                    XCTAssertTrue(error is DecodingError, "\(url.lastPathComponent): \(error)")
                }
                continue
            }
            let manifest = try JSONDecoder().decode(SoundtrackManifest.self, from: data)
            XCTAssertThrowsError(try manifest.validate(limits: limits), url.lastPathComponent) { error in
                XCTAssertEqual((error as? SoundtrackManifestError)?.code, expected, url.lastPathComponent)
            }
        }
    }

    /// The synthetic track the other tests use is itself a valid manifest.
    func testTheSyntheticTrackIsValid() throws {
        XCTAssertNoThrow(try SyntheticSoundtrack.manifest.validate(limits: SoundtrackTestSupport.soundtrack()))
    }

    /// A manifest survives the round trip: what Swift writes, Swift reads.
    func testTheManifestRoundTrips() throws {
        let data = try JSONEncoder().encode(SyntheticSoundtrack.manifest)
        XCTAssertEqual(try JSONDecoder().decode(SoundtrackManifest.self, from: data), SyntheticSoundtrack.manifest)
    }
}
