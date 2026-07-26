import CoreGraphics
import Foundation

/// Where a stop's overlay elements sit on screen, as **pure geometry**.
///
/// Split out of the renderer so it can be tested without drawing anything: the
/// rules here are exactly the kind of thing a visual review is bad at checking
/// and a unit test is good at.
///
/// **Why this exists.** The camera used to dolly into every stop, which
/// guaranteed the vehicle sat dead centre — so a frame-centred card could never
/// collide with it. Since the camera went static (Chiu 2026-07-25) the vehicle is
/// wherever it really is on the map, which can be anywhere.
///
/// **What is and is not allowed to overlap.** The photo card *may* cover the
/// vehicle: it is opaque, it is the subject of the beat, and on a 1920-tall frame
/// a card half the frame high plus its caption cannot always clear a vehicle
/// sitting in the middle. The **name band** (pin + stop name) may not — text
/// printed across the car is what looked broken. So the card is placed first and
/// the name band goes on whichever side of it faces *away* from the vehicle.
public struct RecapStopLayout {
    /// The photo card's rect (CG bottom-left origin). Zero height for the lead-in
    /// beat, which has no card.
    public let cardRect: CGRect
    /// The pin + name band, always clear of the vehicle.
    public let labelRect: CGRect
    /// True when the name band sits above the card rather than below it.
    public let labelIsAboveCard: Bool

    public init(
        anchor: CGPoint,
        cardSize: CGSize,
        labelBandHeight: CGFloat,
        labelBandWidth: CGFloat,
        clearance: CGFloat,
        marginPx: CGFloat,
        frameSize: CGSize
    ) {
        // The card tracks the vehicle horizontally and prefers to sit clear of it
        // vertically; where it cannot, it is clamped into the frame and simply
        // covers the vehicle. Limits leave room for the name band on either side.
        let halfCard = cardSize.height / 2
        let above = anchor.y + clearance + halfCard
        let below = anchor.y - clearance - halfCard
        let topLimit = frameSize.height - marginPx - halfCard - labelBandHeight
        let bottomLimit = marginPx + halfCard + labelBandHeight
        var cardCenterY = above <= topLimit ? above : below
        cardCenterY = min(max(cardCenterY, min(bottomLimit, topLimit)), max(bottomLimit, topLimit))

        let halfWidth = cardSize.width / 2
        let cardCenterX = min(
            max(anchor.x, marginPx + halfWidth),
            max(frameSize.width - marginPx - halfWidth, marginPx + halfWidth)
        )
        cardRect = CGRect(
            x: cardCenterX - halfWidth, y: cardCenterY - halfCard,
            width: cardSize.width, height: cardSize.height
        )

        // The name band goes on the far side of the card from the vehicle, so it
        // never lands on the car even when the card itself had to cover it.
        labelIsAboveCard = anchor.y <= cardRect.midY
        let labelY = labelIsAboveCard ? cardRect.maxY : cardRect.minY - labelBandHeight
        let labelX = min(
            max(cardCenterX - labelBandWidth / 2, marginPx),
            max(frameSize.width - marginPx - labelBandWidth, marginPx)
        )
        labelRect = CGRect(
            x: labelX,
            y: min(max(labelY, marginPx), max(frameSize.height - marginPx - labelBandHeight, marginPx)),
            width: labelBandWidth, height: labelBandHeight
        )
    }

    /// Does the **name band** land on the vehicle? The layout's job is to keep
    /// this false; the card is deliberately exempt (see the type's note).
    public func labelOverlaps(vehicleAt anchor: CGPoint, lengthPx: CGFloat) -> Bool {
        labelRect.intersects(CGRect(
            x: anchor.x - lengthPx / 2, y: anchor.y - lengthPx / 2,
            width: lengthPx, height: lengthPx
        ))
    }
}
