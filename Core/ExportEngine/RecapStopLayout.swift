import CoreGraphics
import Foundation

/// Where a stop's overlay elements sit on screen, as **pure geometry**.
///
/// Split out of the renderer so it can be tested without drawing anything: the
/// rules here are exactly the kind of thing a visual review is bad at checking
/// and a unit test is good at.
///
/// **The pin owns the stop's point** (Chiu 2026-07-26). Everything else — the
/// name pill, then the photo card — stacks off it, so the whole scene visibly
/// grows out of the place the journey actually paused. That ordering *is* the
/// product behaviour: the car arrives there, parks, and hands the spot to the pin.
///
/// It did not used to work this way. The group was pushed clear of the vehicle by
/// the vehicle's own half-length plus a margin — in *pixels*, sized from a 380 px
/// car sprite, which at a wide act framing is nearly three kilometres of ground.
/// A pin meant to mark a stop landed kilometres from it. The car now parks and
/// disappears for the duration of a stop scene (`LinearTimeline.subjectState`),
/// so there is nothing to dodge.
///
/// The only thing that still moves the group is the **frame edge**: a stop hard
/// against the border would otherwise draw half off-screen. The pin is nudged in
/// by the margin and no further, so it stays as close to the truth as being
/// visible allows.
public struct RecapStopLayout {
    /// Where the pin is drawn: the stop's own projected point, moved only far
    /// enough to keep the marker on screen.
    public let pinPoint: CGPoint
    /// The name pill, sitting directly on the pin.
    public let labelRect: CGRect
    /// The photo card, clear of the pin + name group. Zero-sized for the lead-in
    /// beat, which has no card.
    public let cardRect: CGRect
    /// True when the card floats above the pin group rather than below it.
    public let cardIsAbovePin: Bool

    public init(
        anchor: CGPoint,
        cardSize: CGSize,
        pinHeight: CGFloat,
        labelBandHeight: CGFloat,
        labelBandWidth: CGFloat,
        gap: CGFloat,
        marginPx: CGFloat,
        frameSize: CGSize
    ) {
        // The pin: the stop's point, nudged in only to stay visible. The group
        // above it needs room too, so the top clamp accounts for the pill.
        let pinX = Self.clamp(anchor.x, marginPx + labelBandWidth / 2, frameSize.width - marginPx - labelBandWidth / 2)
        let pinY = Self.clamp(anchor.y, marginPx + pinHeight, frameSize.height - marginPx - pinHeight - labelBandHeight)
        pinPoint = CGPoint(x: pinX, y: pinY)

        // The name pill stands on the pin, so reading upward gives point → place.
        let labelBottom = pinY + pinHeight / 2 + gap
        labelRect = CGRect(
            x: Self.clamp(pinX - labelBandWidth / 2, marginPx, max(frameSize.width - marginPx - labelBandWidth, marginPx)),
            y: labelBottom,
            width: labelBandWidth,
            height: labelBandHeight
        )

        guard cardSize.height > 0 else {
            cardRect = CGRect(origin: CGPoint(x: pinX, y: labelRect.maxY), size: .zero)
            cardIsAbovePin = true
            return
        }

        // The card floats clear of the whole pin group, preferring above. It flips
        // below only when there is no room, so a stop high in frame still reads.
        let halfCard = cardSize.height / 2
        let above = labelRect.maxY + gap + halfCard
        let below = pinY - pinHeight / 2 - gap - halfCard
        let fitsAbove = above + halfCard <= frameSize.height - marginPx
        cardIsAbovePin = fitsAbove || below - halfCard < marginPx
        let preferred = cardIsAbovePin ? above : below
        // Last resort: a frame too short for either side clamps the card in, and
        // it may then cover the pin. That is allowed — the card is opaque and it
        // is the subject of the beat; a pin under it is not what breaks the shot.
        let cardCenterY = Self.clamp(
            preferred, marginPx + halfCard, max(frameSize.height - marginPx - halfCard, marginPx + halfCard)
        )
        let halfWidth = cardSize.width / 2
        let cardCenterX = Self.clamp(
            pinX, marginPx + halfWidth, max(frameSize.width - marginPx - halfWidth, marginPx + halfWidth)
        )
        cardRect = CGRect(
            x: cardCenterX - halfWidth, y: cardCenterY - halfCard,
            width: cardSize.width, height: cardSize.height
        )
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, min(lower, upper)), max(lower, upper))
    }
}
