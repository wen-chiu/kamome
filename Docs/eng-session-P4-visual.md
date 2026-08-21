# Engineering session — three visual checks, on the merged routing

**Status: NOT YET RUN (2026-08-21).** Established from source rather than asked:
`MapKitSnapshotProvider` still sets only `displayScale: 1` and no
`userInterfaceStyle`, and `RecapDemoFilmTests.swift:357` still carries the stale
`XCTFail`, so none of items 1–3 or the assertion fix has landed. **Task 0 (confirm
the key) is closed** — key fine per Chiu, 2026-08-21, owner report; no run log
exists, which is why item 3 now carries the confirmation instead of it being a
gate of its own. **Precondition: PR #16 is merged**; this session branches off
`main`.

**Paste the block below as the first message of a fresh Claude Code session.**

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first, then `Docs/current-state.md` (the snapshot — run its staleness check),
`CLAUDE.md`, then `Docs/decisions.md` entries **2026-08-20 (a)–(d)** and both
"Findings — PO/Architecture session" sections in `HANDOFF.md`.

The routing migration landed on `main` in **PR #16** (`e366df2`, `556f828`,
`1cedbd2`, `2d221e0`). **Branch off `main`.** If `main` does not contain
`e366df2`, PR #16 has not merged yet — stop and tell Chiu rather than working
from the feature branch.

This session does not redo the migration. It makes three cheap visual changes
Chiu will judge by looking.

## The reference film

`~/Kamome-films/2026-08-21-iceland-geoapify.mp4` — Iceland, 21 stops, 211.5 s,
rendered on Geoapify on 2026-08-21. It lives outside the repository deliberately
(§0: it is a render of a real trip). **Chiu has judged its routes: the 49 solid
legs are correct** (owner report, 2026-08-21), which closes ADR 2026-08-20 (d)
item 4. Do not re-open it, do not re-litigate the detour gate, and do not treat a
dashed leg as a defect.

That film is also where the halo in item 1 is visible.

## 1 — The route line has a shadow around it. Find out why.

Chiu sees a shadow or halo ring around the solid blue route line in the rendered
film, and wants it gone.

**One verified fact, to save you a wrong start:** it is **not** the configured
glow. `RecapStyle.routeGlowColor` has alpha `0`, and `RecapOverlayRouteDrawing`
guards the glow pass behind `alpha > 0.001`, so that pass does not run. A solid leg
is a single stroke.

**Beyond that, diagnose it — do not accept a theory, including one you form early.**
Reproduce it in a rendered frame first, so you are looking at the artefact and not
at the source. Report the cause before changing anything; if the fix touches shared
drawing state rather than the route's own style, say so, because that is a different
change with a wider blast radius.

## 2 — One map experiment, two dimensions at once

Both of Chiu's requests land on the same object — `MKMapSnapshotterOptions
.traitCollection` in `MapKitSnapshotProvider`, which today sets only
`displayScale: 1`. Do them as **one** render so he sees them together.

- **Dark Apple Maps.** Add `userInterfaceStyle: .dark`. He wants to see whether a
  dark base suits the film better — the souvenir-map direction was always dark.
- **Bigger place labels.** Labels are drawn at fixed *point* sizes, and the snapshot
  is deliberately 1 point == 1 pixel. Raise `displayScale` (try 2, then 3) and divide
  `options.size` by the same factor: identical pixel output, labels 2–3× larger.

⚠️ **The 1:1 mapping is load-bearing** — the comment says so, because `point(for:)`
must agree with frame coordinates and the projection travels with `MapSnapshot`.
Changing scale means correcting that projection by the same factor. Verify it with
the existing golden-frame and continuity gates, not by eye: a projection that is off
by a constant looks plausible in a still frame and drifts in motion.

Expect a second-order effect and report it rather than hiding it: at a higher
display scale MapKit may also choose a different label *density* and POI detail, not
merely a larger size.

## 3 — Render with `car-toy`, and catch the routing line while you do

Chiu wants the next test film to use `car-toy` as the subject. No code change —
it is a subject choice.

**This render carries what used to be task 0.** The keyed path has never been
observed working through the app's own configuration: the only real film so far
was rendered through a locally-run Worker, because the key then in
`Config/Secrets.xcconfig` returned 401. Chiu has since fixed the key and reports
it fine, but **no run log exists**. So report this render's `matchTrip` lines —
`N/M legs routable` and `N reconstructed` — and that UNKNOWN closes without a
separate errand.

If it 401s, **stop and say so.** Do not work around it with a locally-run Worker:
a workaround is what hid this for a day.

Separately, one thing he should know rather than have you act on: the seagull's
film sprite is `seagull/omni.png`; `logo.png` in the same folder is only the S3
picker thumbnail. Its size is `length_fraction` in `vehicles.json`, currently `0.7`.
**Do not change it this round.**

## Not in this session — named so you do not pick them up

- **`body_span_padding` / journey zoom.** Chiu has looked and is leaving it.
- **Film duration.** 211.5 s against `total_duration_max_s: 90` is real and known;
  it is parked with export performance, deliberately.
- **`export.keyframe_interval_frames` and the opening's per-frame snapshotting.**
  Frozen pending the camera-arc Pass 1 render (`Docs/camera-arcs.md`,
  `Docs/eng-session-camera-arc.md`). Do not touch, do not optimise around, do not
  benchmark against.
- **The camera arc itself.** A separate session with its own brief. Nothing here
  should make it harder.
- **Deploying the Worker.** Needs Chiu's Cloudflare account; he is doing it after
  this session.

## One thing you may fix, as its own commit

`RecapDemoFilmTests.swift:357` `XCTFail`s when no MapLibre region exists, then
renders on Apple Maps anyway. Since the 2026-08-08 substrate ADR, Apple Maps **is**
the shipping substrate, so this fails on every run of a film that completed
successfully. Per `Arch.md` §7.3 the assertion is **restated to hold the current
rule**, not deleted — the rule it should encode is that a film renders on whichever
substrate is available, and that falling back is not a failure.

## Verification and reporting

`Arch.md` §12 before any code: Problem → Boundary → Options → Decision →
Verification plan.

Report per §8 levels, and per §7.4 report the test count. The tree was clean on
2026-08-21; still run `git status --short` before quoting a count, and if another
session's uncommitted work is in it, measure in a `git worktree --detach` or say
you could not exclude it (`HANDOFF.md` 3e).

Any guard or assertion you add or change needs a **positive control**: show it going
red when it should, not only green when it should.

Findings go into `HANDOFF.md` under a dated entry. Since the 2026-08-21
reorganisation that file carries live findings only — a finding that exists solely
in your session has not been delivered.

`Arch.md` §14 at the end: "Ready for review", never "done".
```
