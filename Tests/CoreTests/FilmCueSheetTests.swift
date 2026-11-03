import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The film's moments are the picture's own** (`Docs/handoff-music-in-the-film.md`
/// §2.1). The cue sheet reads the functions the overlay reads, so these pin it
/// against the frames themselves: a photograph the music answers is a
/// photograph that appears on that frame, and the refactor that shared the slot
/// math moved no photograph by a frame.
///
/// Synthetic geometry between public places on the shipped tunables, as
/// `ExportQualityMatrixTests` builds it (`CLAUDE.md` §0).
final class FilmCueSheetTests: XCTestCase {
    typealias Place = RecapCoordinate

    private let lisbon = Place(lat: 38.72, lon: -9.14)
    private let porto = Place(lat: 41.15, lon: -8.61)
    private let singapore = Place(lat: 1.36, lon: 103.99)
    private let london = Place(lat: 51.47, lon: -0.45)

    private func shipped() throws -> TrackingConfig.Export { try SoundtrackTestSupport.shipped().export }

    /// One stop per place; a leg in `crossings` is a straight crossing, every
    /// other a 30-vertex road.
    private func trip(_ places: [Place], photos: [Int], crossings: Set<Int> = [], countries: [String]? = nil) -> RecapTrip {
        let stops = places.enumerated().map { index, place in
            RecapTrip.Stop(
                coordinate: place, name: "Stop \(index)", dayLabel: "Day 1",
                photos: (0..<photos[index]).map { .asset("p\(index)-\($0)") }, dwellS: 3600, locality: "Town \(index)"
            )
        }
        let legs = zip(places, places.dropFirst()).enumerated().map { index, pair -> RecapTrip.Leg in
            let crossing = crossings.contains(index)
            let coordinates = crossing ? [pair.0, pair.1] : (0...30).map { step in
                Place(lat: pair.0.lat + (pair.1.lat - pair.0.lat) * Double(step) / 30,
                      lon: pair.0.lon + (pair.1.lon - pair.0.lon) * Double(step) / 30)
            }
            let codes = crossing ? (countries?[index], countries?[index + 1]) : (nil, nil)
            return RecapTrip.Leg(coordinates: coordinates, mode: .drive, provenance: crossing ? .inferred : .reconstructed,
                                 isCrossing: crossing, countryCodes: codes)
        }
        return RecapTrip(legs: legs, stops: stops, title: "Trip", subtitle: "", endCardFigures: [],
                         everyLegRoutabilityEstablished: true)
    }

    private func line(_ start: Place, _ end: Place, count: Int) -> [Place] {
        (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            return Place(lat: start.lat + (end.lat - start.lat) * fraction, lon: start.lon + (end.lon - start.lon) * fraction)
        }
    }

    /// Three committed fixture films: a day drive with two quiet stops and a
    /// stop dense with photographs; a ferry mid-trip; and a long-haul whose
    /// departure plays its photographs over the frozen card (#275).
    private func films() throws -> [(name: String, timeline: LinearTimeline)] {
        let config = try shipped()
        let cases: [(String, RecapTrip)] = [
            ("day drive", trip(line(lisbon, porto, count: 6), photos: [3, 0, 7, 2, 0, 4])),
            ("ferry", trip([Place(lat: 56.0, lon: -4.0), Place(lat: 56.3, lon: -4.6), Place(lat: 56.45, lon: -5.5),
                            Place(lat: 56.6, lon: -6.2), Place(lat: 56.5, lon: -6.4)],
                           photos: [3, 3, 3, 3, 3], crossings: [2], countries: Array(repeating: "GB", count: 5))),
            ("long-haul departure", trip([singapore] + line(london, Place(lat: 51.75, lon: -1.25), count: 4),
                                         photos: [4, 3, 3, 3, 3], crossings: [0],
                                         countries: ["SG", "GB", "GB", "GB", "GB"]))
        ]
        return try cases.map { name, trip in
            (name, try XCTUnwrap(LinearTimeline(trip: trip, config: config, locale: Locale(identifier: "zh-Hant")), name))
        }
    }

    /// The deck on screen at `time`: its first photograph (which deck) and the
    /// one in focus.
    private func deck(_ timeline: LinearTimeline, atTime time: Double) -> (deck: PhotoRef, focus: Int)? {
        for content in timeline.overlayContents(atTime: time) {
            if case let .photoDeck(deck) = content, let first = deck.photos.first { return (first, deck.focusIndex) }
        }
        return nil
    }

    /// The first frame showing whatever begins at `time` — the frame the render
    /// loop draws at `frame / fps`, the same comparison `focusIndex` makes.
    private func frame(at time: Double, fps: Int) -> Int {
        var frame = max(Int((time * Double(fps)).rounded(.up)) - 1, 0)
        while Double(frame) / Double(fps) < time { frame += 1 }
        return frame
    }

    func testEveryPhotoChangeCueIsTheFrameANewPhotographAppears() throws {
        for (name, timeline) in try films() {
            let fps = try shipped().fps
            var changes: Set<Int> = []
            var previous: (deck: PhotoRef, focus: Int)?
            for index in 0..<timeline.frameCount {
                let current = deck(timeline, atTime: Double(index) / Double(fps))
                if let current, let previous, current.deck == previous.deck, current.focus != previous.focus {
                    changes.insert(index)
                }
                previous = current
            }
            let cues = Set(timeline.cueSheet().filter { $0.kind == .photoChanges }.map { frame(at: $0.timeS, fps: fps) })
            XCTAssertFalse(changes.isEmpty, "\(name): the fixture must change photographs, or this tests nothing")
            XCTAssertEqual(cues, changes, "\(name): a photoChanges cue on a frame with no new photograph, or the reverse")
        }
    }

    /// The slot math before it was shared (2026-11-03), kept here as the oracle.
    private func focusBeforeTheRefactor(_ timeline: LinearTimeline, time: Double, window: (start: Double, end: Double),
                                        count: Int) -> Int {
        let zoom = timeline.zoomRamp(window)
        let rotateStart = window.start + zoom
        let slot = max((window.end - zoom) - rotateStart, 1e-6) / Double(count)
        return min(max(Int((time - rotateStart) / slot), 0), count - 1)
    }

    func testFocusIndexIsUnchangedAtEveryFrame() throws {
        let fps = try shipped().fps
        var compared = 0
        for (name, timeline) in try films() {
            for index in 0..<timeline.frameCount {
                let time = Double(index) / Double(fps)
                var windows: [((start: Double, end: Double), Int)] = []
                if let scene = timeline.activeScene(atTime: time) {
                    windows.append((timeline.deckWindow(scene.hold), scene.stop.photos.count))
                }
                if let cut = timeline.departureCut, time >= cut.startS, time < cut.endS {
                    windows.append((timeline.deckWindow(CameraPath.Hold(stopIndex: -1, startS: cut.startS, endS: cut.endS)),
                                    cut.stop.photos.count))
                }
                for (window, photos) in windows where time >= window.start {
                    let count = timeline.affordablePhotoCount(deck: window, requested: photos)
                    XCTAssertEqual(timeline.focusIndex(atTime: time, deck: window, count: count),
                                   focusBeforeTheRefactor(timeline, time: time, window: window, count: count),
                                   "\(name) frame \(index)")
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 1_000, "too few deck frames compared to mean anything")
    }

    func testTheCueSheetReadsTheTimelinesOwnMoments() throws {
        for (name, timeline) in try films() {
            let cues = timeline.cueSheet()
            XCTAssertEqual(cues.map(\.timeS), cues.map(\.timeS).sorted(), name)
            XCTAssertEqual(cues.first?.kind, .opening, name)
            XCTAssertEqual(cues.last?.kind, .endCard, name)
            XCTAssertEqual(try XCTUnwrap(cues.last).timeS, timeline.durationS - timeline.endCardS, accuracy: 1e-9, name)
            let beats = timeline.path.crossingBeatWindowsS
            XCTAssertEqual(cues.filter { $0.kind == .endReveal }.map(\.timeS), timeline.path.endRevealStartS.map { [$0] } ?? [])
            XCTAssertEqual(cues.filter { $0.kind == .crossing }.map(\.timeS), beats.map(\.lowerBound), name)
            XCTAssertEqual(cues.filter { $0.kind == .landing }.map(\.timeS), beats.map(\.upperBound), name)
            // Every arrival is followed by its own stop's departure.
            for arrival in cues where arrival.kind == .stopArrives && arrival.stopIndex != nil {
                XCTAssertTrue(cues.contains { $0.kind == .go && $0.stopIndex == arrival.stopIndex && $0.timeS > arrival.timeS },
                              "\(name): stop \(arrival.stopIndex ?? -1) arrives and never leaves")
            }
        }
    }

    func testTheFixturesCoverEveryKindTheFilmsCanHave() throws {
        let kinds = Set(try films().flatMap { $0.timeline.cueSheet().map(\.kind) })
        XCTAssertEqual(kinds, Set(FilmCue.Kind.allCases).subtracting([.titleCut]),
                       "a kind the fixtures never produce is a kind these tests never check")
    }
}
