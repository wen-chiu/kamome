import Foundation

/// **Travel is earned by what crosses the screen** (ADR file 2026-09-28).
///
/// Chiu, on his New Zealand film: *「車子一直跑浪費一堆時間」* and *「整體長度沒變
/// 這很奇怪」*. The duration plan gives travel a fixed share of the body
/// (1 − `max_hold_fraction`), whatever the camera has to show in it. Framed
/// wide, a road trip crosses few windows, so that share was spent crawling:
/// Iceland's dump crossed 5.7 windows in 80 s (VERIFIED at the desk). Now
/// travel lasts only as long as its windows need at this rate, and the film is
/// shorter by the rest. It never gets longer than the plan.
///
/// Its own type for the same reason `CameraContextConfig` is: `Export` sits at
/// its file-length limit.
public struct TravelPacingConfig: Decodable, Equatable {
    /// Route windows the vehicle crosses per second of travel. **0.6, INFERRED**:
    /// the rate measured on Miyakojima's local film (0.60), whose pace drew no
    /// complaint. What would settle it: Chiu judging a render at 0.5 / 0.6 / 0.8.
    public let windowsPerS: Double

    enum CodingKeys: String, CodingKey {
        case windowsPerS = "windows_per_s"
    }

    public init(windowsPerS: Double) {
        self.windowsPerS = windowsPerS
    }

    /// Travel keeps the plan's share: the default for hand-built test configs,
    /// which pin the films written before travel was earned.
    public static let off = TravelPacingConfig(windowsPerS: 0)

    public var isEnabled: Bool { windowsPerS > 0 && windowsPerS.isFinite }
}
