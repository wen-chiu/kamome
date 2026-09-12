import Foundation

/// **Split out of `RecapAnimationState.swift` on 2026-09-12**, which had reached
/// the 400-line lint ceiling — the same reason `RecapDemoFilmSubstrate` and
/// `RecapStyleEndCard` are their own files. The narrow waist's other three state
/// types stay where they were; this one is the one that grows, because every new
/// thing the film draws arrives here.
///
/// One drawable element active at an instant — **pure data**, no CoreGraphics
/// and no geo→pixel (the renderer projects through the `CameraFrame`, resolves
/// `PhotoRef`s, and generates the QR from `shareURL`). Overlays never mutate or
/// override the camera; the timeline synchronizes any camera move with the
/// content it belongs to. `Equatable`, so a test can assert what the timeline
/// produced without comparing bitmaps.
public enum OverlayContent: Equatable {
    /// The traveled trail up to the subject, leg by leg. Legs rather than one
    /// polyline because they do not all deserve the same stroke: a leg the
    /// pipeline could not confidently reconstruct must read as a guess in the
    /// published film, not as road (PD-1).
    case routeReveal([RecapRouteLeg])
    /// A stop pin on the map with its name label floating clear above the
    /// vehicle (the lead-in beat). `opacity` fades it out as the photo deck
    /// takes over the stop's identity below the card.
    /// `name` is nil when the place is **named by something else in the same
    /// frame** and must not be labelled twice — today only the departure airport,
    /// whose flight-end mark carries the country name instead (ADR 2026-09-05 (c)).
    /// The pin is still drawn; only the type is absent.
    case stopLabel(name: String?, coordinate: RecapCoordinate, detail: String?, opacity: Double)
    /// The enlarged photo deck at a stop.
    case photoDeck(RecapPhotoDeck)
    /// **The boarding pass, during the crossing beat and nowhere else** (Chiu
    /// 2026-09-02). See `RecapJourneyCard` for what is on it and what is
    /// deliberately not.
    case journeyCard(RecapJourneyCard)
    /// **Here, and there** — a Kamome mark on each end of the flight, drawn over
    /// the opening's still frame only (Chiu 2026-09-04).
    ///
    /// The answer to *"地圖放太遠會失去焦點，一開始的畫面會無法明確知道出發地跟
    /// 目的地"* — at 8,891 km MapKit labels neither city and neither coastline is
    /// a recognisable silhouette, so the frame is a texture rather than a place
    /// (`Docs/handoff-type2-films.md` closeout item 1). Two marks say *here* and
    /// *there* without the base map naming anything.
    ///
    /// Since 2026-09-04 each mark carries **the country's name beneath it** —
    /// nothing else, and only here.
    ///
    /// 🔴 **Neither lock is thawed, and the reasons differ.** The **base map**
    /// still draws no label of its own: that is `handoff-P3.5.md` §"Map reference
    /// labels", blocked on a fontstack, and untouched. The
    /// **`Docs/icebox.md` place-name entry** is a *narrative system* — landmark
    /// title cards timed between beats, across the whole film — and this is one
    /// slice of one beat. What is drawn is a Kamome-owned overlay at two
    /// endpoints, which is the shape that entry itself names as the correct one;
    /// it was parked for effort, and the effort here is zero because the boarding
    /// pass has already resolved both names.
    ///
    /// Each end carries **the name the boarding pass already resolved**, never a
    /// second lookup — see `RecapFlightEnd`.
    ///
    /// Both ends are always carried. The origin's *mark* yields to the departure
    /// stop's own pin by cross-fading on `RecapFlightEnd.markOpacity` — they are
    /// the same point — while its name stays up (ADR 2026-09-05 (c)).
    case flightEnds(origin: RecapFlightEnd, destination: RecapFlightEnd, opacity: Double)
    /// **Persistent film chrome** (Chiu 2026-07-31): which day of the trip it is
    /// and how far the journey has come, in the frame's top corners, for the whole
    /// body of the film — driving as well as stopped.
    ///
    /// This is a fact about the *journey at this instant*, which is why it is one
    /// overlay rather than something each stop carries: the distance has to keep
    /// climbing while the car moves, and the day has to be readable on a leg that
    /// belongs to no stop at all. `place` is the stop the film is parked at, and
    /// is nil on the road between them.
    ///
    /// Suppressed under the title and end cards, which are full-bleed and own the
    /// frame for their few seconds.
    case hud(dayLabel: String, place: String?, travelledM: Double)
    /// Opening chrome: trip name + dates/distance.
    case titleChrome(title: String, subtitle: String)
    /// Closing chrome: the trip's name, the film's three figures, and the share
    /// payload the renderer turns into a QR. `shareURL` is nil for the Replay MVP
    /// (PD-4) — the end card shows the Kamome wordmark instead of a code that
    /// resolves to nothing.
    ///
    /// 🔴 **Figures, not sentences** (Chiu 2026-09-05, ADR 2026-09-05 (d)). This
    /// carried `stats: [String]` — laid-out lines like `269 km · 3 stops` — and the
    /// closing card now sets them as a row of three columns, each a large number
    /// over a small label. A renderer that had to split those strings back apart
    /// to find the number would be parsing copy it did not write, in a language it
    /// does not know. So the **pair** crosses the waist and the app layer, which
    /// owns localization, builds it.
    ///
    /// 🔴 **The closing line is not carried here.** It is `RecapWordmark.tagline`,
    /// a brand mark the renderer owns, not trip data (Chiu 2026-09-05) — the same
    /// standing the wordmark beside it has always had.
    case endChrome(title: String, figures: [RecapEndCardFigure], shareURL: String?)
    /// **The base map's credit** — the licence notice the substrate's data
    /// obliges the exported film to carry (ADR 2026-09-12,
    /// `RecapMapAttribution`).
    ///
    /// 🔴 **It is not part of the story, and it is not the timeline's.** Every
    /// other case here is a fact about the journey; this one is a fact about the
    /// tiles. So the timeline never emits it — `FrameCompositor` synthesises it
    /// from the render loop's provider, which is the one object that both knows
    /// which substrate drew the picture and cannot be constructed without one.
    /// That is also what makes it impossible to forget at a call site.
    ///
    /// It carries no opacity, no position and no beat: a credit that any beat
    /// could fade, move or skip is an obligation with a hole in it, and the hole
    /// would be silent.
    case mapCredit(String)
}
