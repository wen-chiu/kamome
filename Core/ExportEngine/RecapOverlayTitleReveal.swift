import CoreGraphics
import Foundation

/// **How far each part of the opening title has arrived** at one frame, 0…1
/// (2026-11-03), and how much of the stack is left as the beat ends. Kept
/// apart because they move differently: an element *rises* as it arrives, but
/// the stack leaves by fading where it stands — tying the rise to the opacity
/// made the type sink on the way out.
struct RecapTitleReveal {
    var band: CGFloat
    var brand: CGFloat
    var name: CGFloat
    var rule: CGFloat
    var meta: CGFloat
    var exit: CGFloat

    /// Fully in: what a still of the settled title draws.
    static let settled = RecapTitleReveal(band: 1, brand: 1, name: 1, rule: 1, meta: 1, exit: 1)
}

extension RecapOverlayRenderer {
    /// The title's entrance at `elapsedS` into a beat of `holdS`, from the
    /// style's choreography — compressed in proportion when the beat is shorter
    /// than the one it was authored for, so the stack always settles and leaves.
    func titleReveal(elapsedS: Double, holdS: Double) -> RecapTitleReveal {
        let tokens = style.titleStack
        let compress = holdS > 0 ? min(1, holdS / tokens.choreographyReferenceS) : 1
        let exitS = tokens.exitS * compress
        let exit = exitS > 0 ? Self.smoothstep((holdS - elapsedS) / exitS) : 1
        func arrival(_ startS: Double, _ durationS: Double) -> CGFloat {
            let span = durationS * compress
            guard span > 0 else { return 1 }
            return CGFloat(Self.easeOut((elapsedS - startS * compress) / span))
        }
        return RecapTitleReveal(
            band: arrival(0, tokens.bandInS),
            brand: arrival(tokens.brandStartS, tokens.elementInS),
            name: arrival(tokens.nameStartS, tokens.elementInS),
            rule: arrival(tokens.ruleStartS, tokens.elementInS),
            meta: arrival(tokens.metaStartS, tokens.elementInS),
            exit: CGFloat(exit)
        )
    }

    /// Draws `body` faded by its arrival and the beat's exit, lowered by what
    /// is left of its rise.
    func withArrival(
        _ arrival: CGFloat, exit: CGFloat, in surface: RenderSurface, _ body: (_ dropY: CGFloat) -> Void
    ) {
        let alpha = arrival * exit
        guard alpha > 0.001 else { return }
        surface.context.saveGState()
        surface.context.setAlpha(alpha)
        body((1 - arrival) * style.titleStack.risePx * surface.scale)
        surface.context.restoreGState()
    }

    private static func easeOut(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
