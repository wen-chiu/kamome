import Foundation
import KamomeConfig

/// §4.5 steps 2–4: what appears over the map, and when.
///
/// Overlay moments are explicit timeline events rather than per-frame
/// decisions wired to the camera's hold state (decisions.md 2026-07-17), so
/// route-photo fly-bys later join as a new `Kind` without touching the frame
/// renderer. The S5 photos toggle maps to `photosEnabled` — off means a
/// route-only animation with no stop cards. Title and end cards are trip
/// chrome, not photo moments, so the toggle never removes them (the end card
/// carries the "Get this route" share hook).
public struct OverlayEvent: Equatable {
    public enum Kind: Equatable {
        /// Photo card + stop name + day badge during the stop's hold (§4.5 step 3).
        case stopCard(stopIndex: Int)
        /// Trip name, dates, distance over the opening (§4.5 step 4).
        case titleCard
        /// Stats + "Get this route" QR over the close (§4.5 step 4).
        case endCard
    }

    public let kind: Kind
    public let startS: Double
    public let endS: Double
}

public enum OverlayTimeline {
    public static func build(
        holds: [CameraPath.Hold],
        config: TrackingConfig.Export,
        photosEnabled: Bool
    ) -> [OverlayEvent] {
        let durationS = config.targetDurationS
        var events = [
            OverlayEvent(kind: .titleCard, startS: 0, endS: min(config.titleCardS, durationS))
        ]
        if photosEnabled {
            events += holds.map { hold in
                OverlayEvent(kind: .stopCard(stopIndex: hold.stopIndex), startS: hold.startS, endS: hold.endS)
            }
        }
        events.append(
            OverlayEvent(kind: .endCard, startS: max(0, durationS - config.endCardS), endS: durationS)
        )
        return events
    }

    /// Events visible at `time`, for the frame renderer.
    public static func active(in events: [OverlayEvent], atTime time: Double) -> [OverlayEvent] {
        events.filter { $0.startS <= time && time < $0.endS }
    }
}
