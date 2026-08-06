import CoreGraphics
import Foundation

/// Where a stop's overlay elements sit on screen, as **pure geometry**.
///
/// Split out of the renderer so it can be tested without drawing anything: the
/// rules here are exactly the kind of thing a visual review is bad at checking
/// and a unit test is good at.
///
/// **The pin owns the stop's point** (Chiu 2026-07-26). Everything else — the
/// stop's name, then the photo card — stacks off it, so the whole scene visibly
/// grows out of the place the journey actually paused. That ordering *is* the
/// product behaviour: the car arrives there, parks, and hands the spot to the pin.
///
/// It did not used to work this way. The group was pushed clear of the vehicle by
/// the vehicle's own half-length plus a margin — in *pixels*, sized from a 300 px
/// car sprite, which at a wide act framing is nearly three kilometres of ground.
/// A pin meant to mark a stop landed kilometres from it. The car now parks and
/// disappears for the duration of a stop scene (`LinearTimeline.subjectState`),
/// so there is nothing to dodge.
///
/// The only thing that still moves the group is the **frame edge**: a stop hard
/// against the border would otherwise draw half off-screen. The pin is nudged in
/// by the margin and no further, so it stays as close to the truth as being
/// visible allows.
///
/// **The group is one cluster and flips as one** (2026-07-31). The photo, the name
/// under it and the progress dots under that are a single composition — the name
/// is the *caption of the photograph*, not a separate map annotation that happens
/// to be nearby. So when a stop sits too high in frame for the card to open above
/// the pin, the whole group mirrors to the other side (pin → card → name) instead
/// of the card alone flipping and leaving its own caption stranded across the
/// frame. Reading from the photo outward is unchanged either way; only which side
/// of the pin the cluster hangs on changes.
public struct RecapStopLayout {
    /// Where the pin is drawn: the stop's own projected point, moved only far
    /// enough to keep the marker on screen.
    public let pinPoint: CGPoint
    /// The stop's name + strap + progress dots, always adjacent to the card.
    public let labelRect: CGRect
    /// The photo card, clear of the pin. Zero-sized for the lead-in beat, which
    /// has no card.
    public let cardRect: CGRect
    /// True when the cluster hangs above the pin (name on the pin, card over it)
    /// rather than below it (card under the pin, name under the card).
    public let cardIsAbovePin: Bool

    public init(
        anchor: CGPoint,
        cardSize: CGSize,
        /// The card's height once fully revealed. The side the cluster hangs on
        /// is decided from this rather than from `cardSize`, so it cannot change
        /// while the card is still growing.
        maxCardHeight: CGFloat,
        pinHeight: CGFloat,
        labelBandHeight: CGFloat,
        labelBandWidth: CGFloat,
        gap: CGFloat,
        marginPx: CGFloat,
        frameSize: CGSize
    ) {
        // The pin: the stop's point, nudged in only far enough to keep **the
        // marker itself** on screen — its own footprint, nothing else.
        //
        // It used to be clamped by `labelBandWidth / 2`, reserving the width of the
        // name band on the X axis (2026-08-06). That is the label's requirement,
        // and the label already clamps itself below; borrowing it here moved the
        // pin off the route by up to half a name band whenever a stop came near the
        // frame edge — which the wide baseline makes routine, since the camera
        // frames the whole trip and the outermost stops sit against the margin.
        // The comment already claimed the pin no longer reserved that space; the
        // code had simply never been changed to match.
        //
        // This is a *drawing* offset, not a coordinate one: the stop's projected
        // point is exact (measured 0 m from the polyline for all 20 NZ stops), and
        // it is the clamp that moved the marker away from it. Distinct from the
        // vertex-versus-segment snap bug, and it survived that fix untouched.
        let pinInset = pinHeight / 2
        let pinX = Self.clamp(anchor.x, marginPx + pinInset, max(frameSize.width - marginPx - pinInset, marginPx))
        let pinY = Self.clamp(anchor.y, marginPx + pinInset, max(frameSize.height - marginPx - pinInset, marginPx))
        pinPoint = CGPoint(x: pinX, y: pinY)

        // How far the cluster reaches from the pin. Identical on both sides —
        // mirroring reorders the same pieces, it does not resize them.
        let cardBlock = cardSize.height > 0 ? cardSize.height + gap : 0
        let reach = pinHeight / 2 + gap + labelBandHeight + cardBlock

        // **Which side is decided from the card's FINAL size, not its current
        // one** (2026-08-01). The card grows across the deck's reveal, so a reach
        // measured from the live size crosses the fits-above threshold *during*
        // the animation — the Miyakojima film flipped above → below → above
        // inside one second. The side a cluster hangs on must be a property of
        // the stop, not of how far through its own animation it happens to be.
        //
        // Camera drift used to be a second way in; the follow camera is now
        // frozen outright while parked, so the pin cannot move mid-scene either.
        let settledCardBlock = maxCardHeight > 0 ? maxCardHeight + gap : 0
        let settledReach = pinHeight / 2 + gap + labelBandHeight + settledCardBlock
        let fitsAbove = pinY + settledReach <= frameSize.height - marginPx
        cardIsAbovePin = fitsAbove || pinY - settledReach < marginPx

        let labelX = Self.clamp(
            pinX - labelBandWidth / 2, marginPx, max(frameSize.width - marginPx - labelBandWidth, marginPx)
        )
        let labelTop = cardIsAbovePin
            ? pinY + pinHeight / 2 + gap + labelBandHeight       // name stands on the pin
            : pinY - pinHeight / 2 - gap - cardBlock             // name hangs under the card
        // Last resort: a frame too short for either side clamps the cluster in,
        // and the card may then cover the pin. That is allowed — the card is
        // opaque and it is the subject of the beat; a pin under it is not what
        // breaks the shot.
        let labelY = Self.clamp(
            labelTop - labelBandHeight, marginPx,
            max(frameSize.height - marginPx - labelBandHeight, marginPx)
        )
        labelRect = CGRect(x: labelX, y: labelY, width: labelBandWidth, height: labelBandHeight)

        guard cardSize.height > 0 else {
            cardRect = CGRect(origin: CGPoint(x: pinX, y: labelRect.maxY), size: .zero)
            return
        }

        // The card always sits directly on top of the name — that is what makes
        // the name read as the photograph's caption. Mirroring moves the pair,
        // never the order inside it.
        let halfCard = cardSize.height / 2
        let cardCenterY = Self.clamp(
            labelRect.maxY + gap + halfCard,
            marginPx + halfCard, max(frameSize.height - marginPx - halfCard, marginPx + halfCard)
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
