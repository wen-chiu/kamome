import CoreGraphics
import Foundation
import ImageIO

/// One of the eight drawn directions a vehicle sprite set covers, at 45° steps
/// clockwise from north. The classic isometric-game technique: rather than spin
/// one image — which only looks right at the angle it was drawn — ship an image
/// per direction, each drawn at that specific 3/4 angle, and pick the nearest.
public enum SpriteDirection: String, CaseIterable {
    // Raw values are the asset filename suffixes: `car-sprite-ne.png` etc.
    case north = "n"
    case northEast = "ne"
    case east = "e"
    case southEast = "se"
    case south = "s"
    case southWest = "sw"
    case west = "w"
    case northWest = "nw"

    /// Compass bearing this direction is drawn at, degrees clockwise from north.
    public var degrees: Double { Double(Self.allCases.firstIndex(of: self) ?? 0) * 45 }

    /// The bucket a travel bearing falls in — nearest 45°, wrapping at 360°.
    /// No interpolation and no rotation: the sprite either is the right drawing
    /// or it is the neighbouring one, which is the whole point of the technique.
    public static func nearest(toBearing bearing: Double) -> SpriteDirection {
        let wrapped = bearing.truncatingRemainder(dividingBy: 360)
        let positive = wrapped < 0 ? wrapped + 360 : wrapped
        let bucket = Int((positive / 45).rounded()) % allCases.count
        return allCases[bucket]
    }
}

/// The bundled hero car, as an **8-direction sprite set** (Chiu 2026-07-25).
///
/// Code-drawn cars hit a quality ceiling, and a single raster sprite only reads
/// correctly at the one angle it was drawn — rotating it continuously breaks the
/// 3/4 perspective at every intermediate angle. So the car ships as eight images
/// (`Resources/car-sprite-{n,ne,e,se,s,sw,w,nw}.png`), and the renderer picks the
/// nearest bucket for the vehicle's heading. Nothing is ever rotated at runtime.
///
/// Decoded once and cached — the render loop asks every frame, and a 900-frame
/// export must not re-decode eight PNGs 900 times. Decoding is deterministic, so
/// the golden-frame gate still holds.
///
/// The eight drawings share one 512×512 canvas and are scaled by canvas, not by
/// content, so the car cannot pulse as it turns. The car fills 52–74% of that
/// canvas depending on direction, which is correct: a car seen side-on really is
/// longer on screen than one seen from behind.
public enum RecapCarSprite {
    private static let cache = SpriteCache()

    /// All eight drawings, or nil if any resource is missing — the caller then
    /// falls back to a vector marker rather than rendering a partial set.
    public static var set: [SpriteDirection: CGImage]? { cache.set }

    private final class SpriteCache: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded = false
        private var cached: [SpriteDirection: CGImage]?

        var set: [SpriteDirection: CGImage]? {
            lock.withLock {
                if !loaded {
                    loaded = true
                    cached = Self.decodeAll()
                }
                return cached
            }
        }

        private static func decodeAll() -> [SpriteDirection: CGImage]? {
            var images: [SpriteDirection: CGImage] = [:]
            for direction in SpriteDirection.allCases {
                guard let url = Bundle.module.url(
                    forResource: "car-sprite-\(direction.rawValue)", withExtension: "png"
                ),
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { return nil }
                images[direction] = image
            }
            return images
        }
    }
}
