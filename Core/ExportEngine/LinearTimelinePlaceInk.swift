import Foundation

/// **The film inks each of the trip's towns as the car reaches it** (Chiu
/// 2026-10-29, ADR 2026-10-29-the-film-inks-each-town-the-car-reaches, which
/// amends ADR file 2026-10-02 §2 and §4).
///
/// Chiu: *「車子快到時，城鎮名才重點…『壓』上地圖，之後一直留著。片尾全路線停留的
/// 1.5 秒裡，整張地圖蓋滿你走過的地方，本身就是一張紀念品地圖。」* The names are on
/// the map from the opening, as a map's are; what the car adds is the mark.
///
/// This file says **when** — which towns the film reaches, and the second each
/// one's ink goes down. It knows nothing of pixels: how the ink looks is
/// `RecapOverlayPlaceInk`'s, and it crosses the waist as `RecapPlaceName.ink`.
extension LinearTimeline {
    /// One reached town's ink: when the pen starts round it, and why then.
    struct PlaceInk: Equatable {
        enum Path: Equatable {
            /// On the road in, finishing as the town's first stop begins its
            /// lead-in, so it is seen being drawn before the stop's own name
            /// takes the town's over.
            case beforeTheLeadIn
            /// The road in was shorter than the pen: drawn as the town's name
            /// comes back, once its first stop has finished presenting itself.
            case asTheNameReturns
        }

        let startS: Double
        let path: Path

        /// The fraction of the stroke down at `time` — a straight fraction of
        /// the time; the pen's own pace is the renderer's.
        func progress(atTime time: Double, drawS: Double) -> Double {
            guard drawS > 0 else { return time >= startS ? 1 : 0 }
            return min(max((time - startS) / drawS, 0), 1)
        }
    }

    /// The towns the film reaches, by the name they are drawn under.
    ///
    /// **A town is reached at the first moment, in film order, that the film
    /// presents any of its stops**: a hold's lead-in, or a quiet stop's passing
    /// label. A town whose stops the film never presents is never inked — in a
    /// film with the photo cards off, that is every town, because such a film
    /// presents no stop at all (`quietStop`).
    ///
    /// **The road in** runs from the end of the last thing the film held — the
    /// previous stop's hold, or a crossing — or from the moment the names are
    /// fully up, to this stop's lead-in. The ink is drawn inside it, so it is
    /// never drawn under another stop's photograph, the boarding pass, or the
    /// zoom the names rise through.
    func placeInks() -> [String: PlaceInk] {
        let names = Self.placeNameKeys(of: stops, journeys: stopJourneys)
        let crossingEndsS = path.crossingBeatWindowsS.map(\.upperBound)
        var inks: [String: PlaceInk] = [:]
        var heldUntilS = journeyStartS
        for hold in holds.sorted(by: { $0.startS < $1.startS }) {
            defer { heldUntilS = max(heldUntilS, hold.endS) }
            guard let returnsS = presentationEndS(of: hold),
                  let name = names[hold.stopIndex], inks[name] == nil else { continue }
            let roadInS = max(heldUntilS, crossingEndsS.filter { $0 <= hold.startS }.max() ?? heldUntilS)
            let startS = hold.startS - placeNameInkDrawS
            inks[name] = startS >= roadInS
                ? PlaceInk(startS: startS, path: .beforeTheLeadIn)
                : PlaceInk(startS: returnsS, path: .asTheNameReturns)
        }
        return inks
    }

    /// When a hold's stop has finished presenting itself — its photo card shut,
    /// or its passing label gone — and its town's name is back; nil when the
    /// film presents nothing for it. The same two cases, and the same test, as
    /// `activeScene` and `quietStop`.
    func presentationEndS(of hold: CameraPath.Hold) -> Double? {
        guard stops.indices.contains(hold.stopIndex), hold.endS > hold.startS else { return nil }
        if !stops[hold.stopIndex].photos.isEmpty { return deckWindow(hold).end }
        return stops.contains(where: { !$0.photos.isEmpty }) ? hold.endS : nil
    }
}
