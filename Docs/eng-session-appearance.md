# The film follows the system appearance — design

**Status:** design recorded 2026-08-28, before any code, per `Arch.md` §12.
Branch `feature/p4-appearance-follows-system`, off `main` at `87d1d4e`.
Chiu's decision of 2026-08-27 is the input, not the output: **the film follows
the device's system appearance, and light mode gets an orange trail instead of
the blue one.** What is designed here is *how* that becomes shipped behaviour
without breaking the reproducibility rule.

This is the first change in the Phase 4 visual series that **moves shipped
behaviour**. The two values reserved for Chiu were closed on **2026-08-29**: the
orange is candidate **B**, `RecapStyle.routeAccent` `#FF8A5B`, and the glow **stays
off on dark**. The ⏳ markers below are kept as the record of what was open and how
it was settled.

---

## 1. Problem

One sentence: *a film's appearance is currently a hard-coded light base under a
preset tuned for a dark one, and it must instead become a single value — captured
once, at export, from the device's system appearance — that selects both the base
map's trait and the overlay palette.*

The legibility half is measured, not taste. On Apple Maps' light base the trail's
cyan `(0.42, 0.87, 0.98)` is the same colour family as the ocean, lakes, rivers
and fjords it crosses. In `~/Kamome-films/2026-08-27-appearance/light/` the
north-coast leg between Sauðárkrókur and Húsavík reads as a fjord, and the
south-coast leg past Hvannadalshnúkur disappears into the sea it runs beside. On
the dark still, same frame, same subject size, the trail is the hero of the frame.
That is why the preset was tuned dark in the first place (`Docs/decisions.md`
2026-07-22), and why the substrate ADR of 2026-08-15 quietly invalidated the
tuning without anyone re-tuning it.

## 2. Boundary

Three layers are touched, and the split matters:

| layer | what it owns here | file |
|---|---|---|
| **Story / style** | the appearance *value*, and the palette it selects | `Core/ExportEngine/RecapAppearance.swift` (new), `RecapStyle.swift` |
| **Rendering** | turning that value into a MapKit trait; declaring when a substrate cannot honour it | `MapKitSnapshotProvider.swift`, `RecapRenderers.swift`, `App/Services/MapLibreSnapshotProvider.swift` |
| **Composition boundary** | *capturing* the value once, at the moment of export | `UI/Recap/RecapView.swift`, `UI/Recap/RecapModel.swift` |

**Why a new domain type rather than reusing `MapKitSnapshotProvider.Appearance`.**
That enum is a *provider* type — it exists to name a `UIUserInterfaceStyle`
without importing UIKit. The trail colour is Kamome's own graphics, drawn by
`RecapOverlayRouteDrawing` over whatever the base map returned; it is not the base
map's colour. Having `RecapStyle` reach into a renderer's nested enum to choose
its own palette inverts the dependency the project protects (`PO.md`, "The Story
layer must not depend on the current rendering substrate"). One domain-level
`RecapAppearance` in the export-engine module, consumed *by* the renderer, points
the dependency the right way and is the only value either side reads.

## 3. Options

### Option A — appearance is a `TrackingConfig.Export` key

`export.appearance: "light" | "dark" | "system"`, read by `RecapModel`.

- **for:** no new type; matches "all tunables in config".
- **against:** it is not a tunable. It is ambient device state, and the config
  file is committed — a key here ships an answer to the question Chiu explicitly
  deferred (the manual picker is *not in this session*). It also puts a product
  decision in infrastructure, which `PO.md` names as a coherence failure.
  **Rejected.**

### Option B — the renderer reads the trait, the style follows the renderer

`MapKitSnapshotProvider` reads `UITraitCollection.current` itself; `RecapStyle`
asks the provider which appearance it got.

- **for:** one read, no plumbing through the UI.
- **against:** this is precisely what ADR 2026-08-15 forbids. `UITraitCollection.current`
  inside `snapshot(_:)` is an environment read **inside the render loop**, on a
  detached task, once per keyframe — a film could legally change appearance
  mid-render if the user toggled dark mode, and no gate could reproduce it. It
  also makes the style a function of the substrate. **Rejected.**

### Option C — one value, captured at the composition boundary, threaded down ✅

`RecapAppearance` is captured in `RecapView` from `@Environment(\.colorScheme)`
at the instant the export button is tapped, handed to
`RecapModel.startExport(appearance:)`, resolved once against the chosen
substrate, and passed as an explicit parameter to both
`RecapStyle.modernMinimal(_:)` and `MapKitSnapshotProvider(displayScale:appearance:)`.
Nothing downstream reads the environment.

- **for:** identical in shape to the seed the ADR describes — chosen at
  `RecapModel`, never generated inside `ExportEngine`, constant for the whole
  render. `RecapStyle.modernMinimal` becomes a **function of the appearance**, so
  no caller — app, harness or test — can obtain a preset without stating which
  appearance it is for. That is the corollary requirement ("every golden-frame and
  still test pins the appearance explicitly") enforced by the type system rather
  than by discipline.
- **against:** four call sites gain an argument, and `RecapView` needs the
  environment value. Real plumbing, small.

**Decision: Option C.**

## 4. How the three constraints are met

### 4.1 Reproducibility

ADR 2026-08-15 requires variation to enter as a seed: chosen at the composition
boundary, persisted with the export, re-renderable. Mapped onto appearance:

- **Chosen at the composition boundary** — ✅ `RecapView` → `startExport(appearance:)`.
  One read, at the tap, on the main actor.
- **Constant for the render** — ✅ it is a `let` captured before `Task.detached`,
  passed into the compositor's style and the provider's initialiser. There is no
  path by which the render loop can observe a change.
- **Persisted with the export** — ⚠️ **not fully met, and this is stated rather
  than papered over.** There is no export record in the schema
  (`Core/Persistence/AppDatabase.swift` has no `export` table) — the seed feature
  that would create one is deferred by the same ADR. What lands instead: the
  resolved appearance is written into the existing
  `KamomeLog.recap.notice("film: …")` line, which is already the record of what a
  render was. So a finished film's appearance is recoverable from the log, and
  when the export record arrives it has exactly one obvious field to carry.
  **Until then, re-exporting the same trip under a different system appearance
  produces a different film, and Kamome cannot tell you which one you have except
  from the log.** That is a known gap with a named owner (the seed feature), not a
  silent one.
- **Gates never inherit an ambient appearance** — ✅ by construction:
  `modernMinimal` takes the appearance as a parameter, so a test cannot get a
  preset without naming one, and `MapKitSnapshotProvider`'s `appearance` argument
  loses its default for the same reason. Note that nothing in the suite read
  `UITraitCollection.current` before this change either; the risk being closed is
  the one this change would otherwise *introduce*.

### 4.2 Where the appearance lives

`RecapAppearance` in `Core/ExportEngine`, beside `RecapStyle`. It selects:

1. the overlay palette — `RecapStyle.modernMinimal(.light)` / `(.dark)`;
2. the base map's trait — `MapKitSnapshotProvider` maps it to
   `UITraitCollection(userInterfaceStyle:)` at the one place UIKit is already
   imported, and its nested `Appearance` enum is deleted as a duplicate concept.

**One substrate cannot honour it.** The MapLibre souvenir map is dark by
construction (`Config/RecapThemes/modern-minimal.json`: `#08111A`, `#04070C`, …).
If a `.pmtiles` region were ever installed, a light-preset overlay would render
over a dark base — the exact inversion that produced the halo defect. So
`MapRendererCapabilities` gains `fixedAppearance: RecapAppearance?` (nil = honours
what it is asked) and `RecapModel` resolves
`provider.capabilities.fixedAppearance ?? requested`. This is the same shape the
file already uses one line away for `followHeadingUp && supportsHeadingUp`, and
the same rule: **a renderer declares what it cannot do rather than silently
ignoring it.**

### 4.3 `UITraitCollection.current` is main-actor, the export is detached

Not read at all. `RecapView` is a SwiftUI view; `@Environment(\.colorScheme)` is
the supported main-actor read of the same state and additionally honours any
`.preferredColorScheme` override in the hierarchy, which `UITraitCollection.current`
inside a model method would not. `RecapModel` is already `@MainActor`, so the
value crosses into `Task.detached` as a captured `Sendable` `let`. Three call
sites in `RecapView` pass it (`recap_export`, `recap_export_again`, and the
retry-after-failure button).

## 5. The palette — what actually needs to differ

Enumerated from source (grep-VERIFIED consumers), before any render. Judgements
marked ⏳ are Chiu's, from the stills this session hands over.

| token | today (`modernMinimal`) | who draws it | differs by appearance? |
|---|---|---|---|
| `routeColor` | cyan `(0.42,0.87,0.98)` | `RecapOverlayRouteDrawing:52` | **YES — decided.** ⏳ which orange |
| `routeInferredColor` | same cyan @ α0.55 | `:39` | **YES — derived.** Must follow the trail's hue and stay visibly weaker |
| `routeGlowColor` | α0 (pass off) | `:46` | ⏳ **dark reopens it** — `a58942d` turned it off *because the base was light* |
| `routeGlowWidthMultiple` | 2.6 (preset leaves the default) | `:48` | only if the glow returns; the retired preset used 3.0 |
| `gradeColor` | cool wash `(0.05,0.10,0.19)` @ α0.16 | `FrameCompositor:124` | ⏳ likely — a cool dark wash over a light base is what greys it |
| `vignetteColor` / `vignetteStrength` | black, 0.42 | `FrameCompositor:131` | ⏳ — black corners cost more on a pale base |
| `chromeScrimColor` | dark `(0.02,0.04,0.07)` @ α0.55 | `Chrome:193,214,219` | ⏳ **never judged on light** — title/end cards |
| `chromeTitleColor` / `chromeMetaColor` | near-white / light grey | `Chrome:66,72,78,122,130,168` | follows the scrim; light-on-dark is coherent either way *if the scrim stays dark* |
| `chromeAccentColor` | orange `(0.95,0.55,0.32)` | `Chrome:137,239–241` | **no** — and see §6, it is why the trail's orange is constrained |
| `deckMatteColor` | white | `Deck:130` | **no** — it is the photo's keyline, white on both |
| `cardColor` | dark @ α0.90 | **no consumer** | **no — dead token** (`HANDOFF.md` 2026-08-28 finding 3) |
| `cardTextColor` | near-white | **no consumer** | **no — dead token** |
| `markerColor` | red | **no consumer** | **no — dead token** |
| `markerAccentColor`, `markerOutlineColor` | near-white, near-black | `RecapSubjectRenderer:76` | fallback-only path (sprite load failure) |
| `fallbackMarkerColor` | white | `RecapSubjectRenderer:76` | fallback-only, but a **white** gull on a light base is the one that would need it if that path ever ships |

**Tokens the brief's list omits and that are on screen in the reviewed frame:**
`hudPillColor` (dark pill @ α0.72) and `hudTextColor` (near-white) —
`RecapOverlayHUDDrawing:42,54,77`, the "Day 9" / "1,594 km" row; and
`labelTextColor` (white type) with `labelShadowColor` — `RecapOverlayRenderer:216`.
The HUD pill survives on light in the 2026-08-27 still. The stop label is not in
that frame and is handed over separately.

## 6. Which orange — the sweep, and the constraint nobody named

Chiu said *start from the orange Kamome already has*, naming `chromeAccentColor`
`(0.95, 0.55, 0.32)`. There is a **second** orange already in the file, and it is
the more interesting one:

```swift
/// `--route: #FF8A5B` — the prototype's single warm accent, shared by the
/// trail's brand colour, the active progress dot and the stop's strap line,
/// so the film has one accent rather than three near-misses.
public static let routeAccent = CGColor(srgbRed: 1, green: 0.541, blue: 0.357, alpha: 1)
```

`RecapStyle.routeAccent` is `#FF8A5B` — **the colour the validated web prototype
drew the route in** (`Docs/prototype/recap_engine.html`, `--route`), already
shipped in Kamome as `deckDotOnColor` and `labelDetailColor`. So "the trail is
orange" is not a new direction; it is the prototype's direction, which the dark
souvenir map's cyan overrode.

The constraint that follows: **the trail's orange and the end card's mark are
both on screen in the same film.** `chromeAccentColor` draws the brand mark and
the closing line (`Chrome:137,239–241`). Two near-miss oranges is the failure the
`routeAccent` comment names out loud — and the file already has two. Whichever
candidate wins, there is a case for collapsing the pair; that is Chiu's call and
is **not** done in this session.

Sweep, one frame (`t≈114.3 s`, the frame that settled the subject size), light
base, displayScale 2, each candidate rendered **with its derived dashed variant**:

| | value | why it is a candidate |
|---|---|---|
| **A** | `(0.95, 0.55, 0.32)` | `chromeAccentColor` exactly — the value Chiu named; zero new colours in the film |
| **B** | `(1.0, 0.541, 0.357)` `#FF8A5B` | `RecapStyle.routeAccent` — the prototype's own route colour, already in the file and already on screen as the dot and strap |
| **C** | `(0.96, 0.42, 0.15)` | deeper and more saturated — the hedge against a pale base: A and B are light oranges, and the terrain they cross is beige and pale green, not black |

The dashed variant is derived, not chosen: same hue, α0.55, `routeInferredWidthMultiple`
0.65. It cannot be judged apart from its solid, which is why each candidate is
handed over as a pair.

## 7. The glow, settled in the same batch

`a58942d` disabled the glow **because the base was light**, and its own message
says the pass "is the right treatment again the day a dark base returns". Chiu
accepted "the halo is gone" from film A, which was rendered light. Dark therefore
reopens it (`HANDOFF.md` finding 8). Two dark stills, same frame, one variable:
`routeGlowColor` α **0** vs α **0.32** at `routeGlowWidthMultiple` 3.0 — the
values the preset carried until 2026-08-22.

Worth stating in advance so the render is read honestly: in the 2026-08-27 dark
still the trail already reads strongly **without** any glow. That is a prediction,
not a verdict; both stills are rendered and Chiu looks.

## 8. Verification plan (`Arch.md` §8)

- **Level 1 — Build/Test.** `xcodegen generate`, full `xcodebuild … test`,
  `swiftlint`. Test count reported before and after (§7.4).
- **Level 2 — Behavioural.**
  - New always-on guards, each shown red by a positive control before being
    accepted: (a) the dashed leg is derived from the trail and stays strictly
    weaker in **both** appearances; (b) the light preset's trail is not in the
    base map's blue family — the *measured* reason for the change, held as a rule
    rather than as a value; (c) a substrate that declares a fixed appearance wins
    over the requested one.
  - Renders: the three-candidate orange sweep (light) and the glow pair (dark),
    same frame, handed to Chiu. He judges; nothing about the *values* is
    self-certified here.
- **Level 3 — Architectural.** Story→Rendering direction preserved
  (`RecapStyle` names no renderer type; the renderer consumes the domain value);
  no config key added for an ambient value; the ADR-2026-08-15 shape (captured at
  the composition boundary, constant for the render) held, with the persistence
  half explicitly deferred in §4.1 rather than assumed.

## 9. Explicitly not in this session

A manual appearance picker; the camera arc; the Worker and its app-side wiring;
`subject_length_px`; the car sprite colliding with the Hvannadalshnúkur label;
the 3× raster deviation; collapsing the two existing oranges (§6).
