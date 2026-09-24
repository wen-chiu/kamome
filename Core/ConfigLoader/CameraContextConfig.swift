import Foundation

/// **The context floor for camera areas** (ADR 2026-09-24 (e)).
///
/// Chiu, on the Miyakojima film framed area by area: *「宮古島的當地行程又有點zoom
/// in得太近了……最少可以看得出來在哪裡」*, then *「旅程地點不同 需要zoom的比例也不同」*.
/// A town area had fallen to `camera_span_m` (1.9 km measured), a scale at which
/// nothing in frame says where it is. The fix is relative, not a bigger metre
/// floor: an area is never framed more than `contextDepth` times deeper than
/// the place it sits in, where the place is found from the trip's own stops
/// (`CameraPath.ContextLadder`).
///
/// Its own type rather than three more flat keys on `Export` because that
/// struct sits at its file-length limit; top level rather than nested so its
/// `CodingKeys` stay inside SwiftLint's nesting budget.
public struct CameraContextConfig: Decodable, Equatable {
    /// How many times deeper than its parent place an area may be framed.
    /// **5, INFERRED**: the geometric mean of the two depths Chiu judged on
    /// Miyakojima, 1.7× (19 km, too wide) and 17× (1.9 km, too tight).
    public let contextDepth: Double
    /// The floor never exceeds this. On a road trip the level above a town is
    /// the whole route, a line rather than a place a viewer recognises, and
    /// dividing it would frame Reykjavík at ~175 km. **10 km, INFERRED** — about
    /// city scale.
    public let contextSpanMaxM: Double
    /// A spanning-tree link longer than this many times the longest link below
    /// it (or `camera_span_m`, whichever is larger) starts a new level of place:
    /// town → island → country. **3, INFERRED** from the committed fixtures
    /// (`Tools/stop-scale-ladder.py`).
    public let contextLevelBreakRatio: Double

    enum CodingKeys: String, CodingKey {
        case contextDepth = "context_depth"
        case contextSpanMaxM = "context_span_max_m"
        case contextLevelBreakRatio = "context_level_break_ratio"
    }

    public init(contextDepth: Double, contextSpanMaxM: Double, contextLevelBreakRatio: Double) {
        self.contextDepth = contextDepth
        self.contextSpanMaxM = contextSpanMaxM
        self.contextLevelBreakRatio = contextLevelBreakRatio
    }

    /// No floor beyond `camera_span_m`: the default for hand-built test configs,
    /// which pin the films written before the floor existed.
    public static let off = CameraContextConfig(
        contextDepth: .infinity, contextSpanMaxM: 0, contextLevelBreakRatio: .infinity
    )

    /// False for `off`, and for any depth that could not make a frame wider.
    public var isEnabled: Bool { contextDepth.isFinite && contextDepth >= 1 }
}
