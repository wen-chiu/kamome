import Foundation

/// **A moment in the film the music can answer** (`Docs/handoff-music-in-the-film.md`
/// §2.1): when the car sets off, when a stop arrives, when a photograph changes.
///
/// A cue carries a kind, a film time and, where one applies, the index of the
/// stop it belongs to — **never a coordinate, a name or a country** (§0 by
/// construction: a cue sheet can be logged, measured and tested without
/// carrying where the trip went).
public struct FilmCue: Codable, Equatable {
    public enum Kind: String, CaseIterable, Codable {
        /// The first frame.
        case opening
        /// The title card's held frame cuts to the film proper (`titleCutS`).
        case titleCut
        /// The car sets off: when the journey starts, then as each hold ends.
        case go
        /// A stop with photographs is reached; its deck plays over the hold.
        /// Also the departure's photographs over a frozen-card opening, with no
        /// stop index (the departure is not on this map).
        case stopArrives
        /// A stop with no photographs to show: named on the map and passed.
        case quietStop
        /// The deck brings its next photograph into focus. Never the first —
        /// that one arrives with the deck itself.
        case photoChanges
        /// A crossing beat begins: the stretch with no road under it.
        case crossing
        /// A crossing beat ends: the road resumes on the far side.
        case landing
        /// The closing reveal of the whole route begins.
        case endReveal
        /// The end card arrives. The music's last chord belongs here.
        case endCard
    }

    public let kind: Kind
    public let timeS: Double
    /// The stop the cue belongs to, indexed like the timeline's stops; nil for
    /// a cue that belongs to no stop.
    public let stopIndex: Int?

    public init(kind: Kind, timeS: Double, stopIndex: Int? = nil) {
        self.kind = kind
        self.timeS = timeS
        self.stopIndex = stopIndex
    }
}

extension LinearTimeline {
    /// **The film's moments, read off the timeline**, sorted by time.
    ///
    /// Derived, never stored, and never re-computed by a copy: every time here
    /// comes from the function the picture already uses — `activeScene` and
    /// `quietStop` decide what a hold is, `deckWindow`, `affordablePhotoCount`
    /// and `photoSlotStartsS` decide when a photograph changes — so a pacing
    /// change moves the music with the picture, and `FilmCueSheetTests` pins
    /// that each `photoChanges` cue is the frame a new photograph appears.
    public func cueSheet() -> [FilmCue] {
        var cues = [FilmCue(kind: .opening, timeS: 0)]
        if let titleCutS { cues.append(FilmCue(kind: .titleCut, timeS: titleCutS)) }
        cues.append(FilmCue(kind: .go, timeS: journeyStartS))
        cues += departureCues()
        for hold in holds { cues += holdCues(hold) }
        for beat in path.crossingBeatWindowsS {
            cues.append(FilmCue(kind: .crossing, timeS: beat.lowerBound))
            cues.append(FilmCue(kind: .landing, timeS: beat.upperBound))
        }
        if let reveal = path.endRevealStartS { cues.append(FilmCue(kind: .endReveal, timeS: reveal)) }
        cues.append(FilmCue(kind: .endCard, timeS: durationS - endCardS))
        // Stable for equal times, so a stop's arrival stays ahead of its own
        // photographs whatever order the kinds were appended in.
        return cues.enumerated()
            .sorted { ($0.element.timeS, $0.offset) < ($1.element.timeS, $1.offset) }
            .map(\.element)
    }

    /// What one hold contributes: its arrival (or its quiet pass), its
    /// photographs, and the car setting off again. A hold nothing is drawn for —
    /// zero length, or a route-only film's stop — contributes only its `go`.
    private func holdCues(_ hold: CameraPath.Hold) -> [FilmCue] {
        var cues: [FilmCue] = []
        if let scene = activeScene(atTime: hold.startS), scene.hold == hold {
            cues.append(FilmCue(kind: .stopArrives, timeS: hold.startS, stopIndex: hold.stopIndex))
            cues += photoChangeCues(window: deckWindow(hold), photos: scene.stop.photos.count, stopIndex: hold.stopIndex)
        } else if let quiet = quietStop(atTime: hold.startS), quiet.hold == hold {
            cues.append(FilmCue(kind: .quietStop, timeS: hold.startS, stopIndex: hold.stopIndex))
        }
        if hold.endS > hold.startS { cues.append(FilmCue(kind: .go, timeS: hold.endS, stopIndex: hold.stopIndex)) }
        return cues
    }

    /// The departure's photographs over a frozen-card opening (#275): the same
    /// deck on the same envelope as a stop's, so the same cues.
    private func departureCues() -> [FilmCue] {
        guard let cut = departureCut, !cut.stop.photos.isEmpty, cut.endS > cut.startS else { return [] }
        let window = deckWindow(CameraPath.Hold(stopIndex: -1, startS: cut.startS, endS: cut.endS))
        return [FilmCue(kind: .stopArrives, timeS: cut.startS)]
            + photoChangeCues(window: window, photos: cut.stop.photos.count, stopIndex: nil)
    }

    /// Every slot start after the first, for as many photographs as the window
    /// affords — exactly the ones `overlayContents` will bring into focus.
    private func photoChangeCues(
        window: (start: Double, end: Double), photos: Int, stopIndex: Int?
    ) -> [FilmCue] {
        let shown = affordablePhotoCount(deck: window, requested: photos)
        return photoSlotStartsS(deck: window, count: shown).dropFirst()
            .map { FilmCue(kind: .photoChanges, timeS: $0, stopIndex: stopIndex) }
    }
}
