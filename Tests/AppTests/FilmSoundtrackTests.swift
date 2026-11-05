@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomePersistence
import XCTest

/// **The app's half of the film's music** (`Docs/handoff-music-in-the-film.md`
/// §2.4, §4.2, §4.3): the bundled catalog is whole, 「換音樂」 lists what §4.2
/// says, and a version-1 analysis row keeps serving the photo pick while its
/// mood reads as neutral.
final class FilmSoundtrackTests: XCTestCase {
    private let config = AppConfig.loadOrDie()

    // MARK: - The bundle

    /// Every track the catalog lists is in the app, valid, and has its audio —
    /// the app half of `Scripts/check-soundtrack-manifests.sh`.
    func testEveryBundledTrackLoadsWithItsAudio() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: SoundtrackCatalog.catalogResource, withExtension: "json"))
        let listed = try XCTUnwrap(
            (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["tracks"] as? [String]
        )
        let catalog = SoundtrackCatalog.load(bundle: .main, limits: config.soundtrack)
        XCTAssertFalse(listed.isEmpty)
        XCTAssertEqual(catalog.manifests.map(\.id).sorted(), listed.sorted(), "a listed track was refused on load")
        for manifest in catalog.manifests {
            XCTAssertNotNil(catalog.audioURL(for: manifest), "\(manifest.id) has no audio in the bundle")
            XCTAssertNotNil(SoundtrackMood(rawValue: manifest.mood), "\(manifest.id): unknown mood")
        }
    }

    // MARK: - 「換音樂」

    private func track(_ id: String, mood: SoundtrackMood) -> SoundtrackManifest {
        let base = SyntheticSoundtrack.manifest
        return SoundtrackManifest(
            id: id, style: base.style, mood: mood.rawValue, file: id + ".m4a", durationS: base.durationS,
            bpm: base.bpm, beatsPerBar: base.beatsPerBar, firstDownbeatS: base.firstDownbeatS,
            tempoDriftBpm: base.tempoDriftBpm, sections: base.sections, sectionsConfirmed: false,
            finalHitBar: base.finalHitBar, tailS: base.tailS, integratedLufs: base.integratedLufs,
            truePeakDbtp: base.truePeakDbtp, provenance: base.provenance
        )
    }

    private func film(current: String?, ranking: [String]?) throws -> FilmRecord {
        let basis = try ranking.map {
            String(bytes: try JSONEncoder().encode(FilmSoundtrackBasis(cues: [], ranking: $0)), encoding: .utf8)
        } ?? nil
        return FilmRecord(
            id: "f", tripId: "t", relativePath: "Films/f.mp4", format: "mp4", createdAt: 0, durationS: 60,
            appearance: "light", recapMode: "highlight", soundtrackId: current,
            soundtrackPlanVersion: ranking == nil ? nil : FilmSoundtrackBasis.planVersion, soundtrackBasis: basis
        )
    }

    private var catalog: SoundtrackCatalog {
        SoundtrackCatalog(manifests: [
            track("d1", mood: .depart), track("c1", mood: .cruise), track("e1", mood: .epic), track("d2", mood: .depart)
        ], bundle: .main)
    }

    func testChangeMusicListsTheCurrentTheNextTwoAndNoMusic() throws {
        let options = try XCTUnwrap(FilmMusicChange.options(for: try film(current: "c1", ranking: ["d1", "c1", "e1", "d2"]),
                                                            catalog: catalog))
        XCTAssertEqual(options.map(\.trackId), ["c1", "d1", "e1", nil])
        XCTAssertEqual(options.map(\.isCurrent), [true, false, false, false])
        XCTAssertEqual(options.map(\.mood), [.cruise, .depart, .epic, nil], "labelled by mood, never by region")
    }

    func testASilentFilmMarksNoMusicAndASecondTakeOfAMoodIsNumbered() throws {
        let options = try XCTUnwrap(FilmMusicChange.options(for: try film(current: nil, ranking: ["d1", "d2"]),
                                                            catalog: catalog))
        XCTAssertEqual(options.map(\.trackId), ["d1", "d2", nil])
        XCTAssertEqual(options.map(\.take), [1, 2, 1])
        XCTAssertEqual(options.last?.isCurrent, true)
    }

    func testAFilmMadeBeforeMusicIsNotOfferedAChange() throws {
        XCTAssertNil(FilmMusicChange.options(for: try film(current: nil, ranking: nil), catalog: catalog))
    }

    // MARK: - The analyser's two versions

    private func row(_ id: String, version: Int, luminance: Double?) -> PhotoAnalysisRecord {
        PhotoAnalysisRecord(phAssetId: id, version: version, outcome: .analyzed, quality: 0.5,
                            sceneLabels: luminance == nil ? nil : PhotoMood.Label.mask([.mountain]),
                            luminance: luminance, saturation: luminance, warmth: luminance.map { _ in 0 }, analyzedAt: 0)
    }

    /// A version-1 row has no mood: only version-2 rows count, and with none the
    /// mood is neutral and the film's shape decides (§2.4).
    func testOnlyVersionTwoRowsCarryAMood() {
        let stop = RecapTrip.Stop(coordinate: RecapCoordinate(lat: 0, lon: 0), name: "A", dayLabel: "",
                                  photos: [.asset("old"), .asset("new")], dwellS: 1)
        let trip = RecapTrip(legs: [], stops: [stop], title: "", subtitle: "", endCardFigures: [])
        let old = ["old": row("old", version: 1, luminance: nil)]
        XCTAssertEqual(FilmSoundtrack.photoMood(trip: trip, analyses: old, nightLuminanceMax: 0.18), .neutral)
        let both = old.merging(["new": row("new", version: PhotoAnalysisVersion.current, luminance: 0.5)]) { $1 }
        let mood = FilmSoundtrack.photoMood(trip: trip, analyses: both, nightLuminanceMax: 0.18)
        XCTAssertEqual(mood.photoCount, 1)
        XCTAssertEqual(mood.landscapeShare, 1)
    }
}
