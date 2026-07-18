import Foundation

/// §4.5 steps 2–3: what appears over the map, and when.
///
/// Overlay moments are explicit timeline events rather than per-frame
/// decisions wired to the camera's hold state (decisions.md 2026-07-17), so
/// route-photo fly-bys later join as a new `Kind` without touching the frame
/// renderer. The S5 photos toggle maps to `overlaysEnabled` — off means a
/// route-only animation with an empty event list.
public struct OverlayEvent: Equatable {
    public enum Kind: Equatable {
        /// Photo card + stop name + day badge during the stop's hold (§4.5 step 3).
        case stopCard(stopIndex: Int)
    }

    public let kind: Kind
    public let startS: Double
    public let endS: Double
}

public enum OverlayTimeline {
    public static func build(holds: [CameraPath.Hold], overlaysEnabled: Bool) -> [OverlayEvent] {
        guard overlaysEnabled else { return [] }
        return holds.map { hold in
            OverlayEvent(kind: .stopCard(stopIndex: hold.stopIndex), startS: hold.startS, endS: hold.endS)
        }
    }

    /// Events visible at `time`, for the frame renderer.
    public static func active(in events: [OverlayEvent], atTime time: Double) -> [OverlayEvent] {
        events.filter { $0.startS <= time && time < $0.endS }
    }
}
