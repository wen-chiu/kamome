# Engineering session — confirm the API, then look at the film

**Status: run outcome NOT RECORDED (as of 2026-08-21).** No document records
whether this session ran or how task 0 (keyed 200 confirmation) came out —
confirm with Chiu before running or re-running it.

**Paste the block below as the first message of a fresh Claude Code session.**

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first, then `CLAUDE.md`, then `Docs/decisions.md` entries **2026-08-20 (a)–(d)**
and `HANDOFF.md`'s "Findings — PO/Architecture session (2026-08-20)".

The routing migration is done and on `feature/geoapify-routing` (`e366df2`,
`556f828`, `1cedbd2`, plus Chiu's `2d221e0`). This session does not redo it. It
confirms the API works, then makes three cheap visual changes Chiu will judge by
looking.

## 0 — Before anything else: confirm routing actually works

Chiu rotated the key. The previous session was blocked by a key returning 401 and
had to render through a locally-run Worker.

**First task, and everything else waits on it:** confirm a keyed build routes for
real. One routed leg returning 200 through the app's own configuration is enough.
Report the `matchTrip` log line.

If it still 401s, **stop and say so** — do not work around it with a local Worker
this time. A workaround is what hid this for a day.

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

## 3 — Render with `car-toy`, not the seagull

Chiu wants the next test film to use `car-toy` as the subject. No code change —
it is a subject choice.

Separately, one thing he should know rather than have you act on: the seagull's
film sprite is `seagull/omni.png`; `logo.png` in the same folder is only the S3
picker thumbnail. Its size is `length_fraction` in `vehicles.json`, currently `0.7`.
**Do not change it this round.**

## Not in this session — named so you do not pick them up

- **`body_span_padding` / journey zoom.** Chiu has looked and is leaving it.
- **Film duration.** 211.5 s against `total_duration_max_s: 90` is real and known;
  it is parked with export performance, deliberately.
- **`export.keyframe_interval_frames` and the opening's per-frame snapshotting.**
  Frozen pending a camera-transition design conversation. Do not touch, do not
  optimise around, do not benchmark against.
- **Deploying the Worker.** Needs Chiu's Cloudflare account.
- **Judging whether any of the 49 solid legs is a wrong road.** That is Chiu's call
  from the film (ADR 2026-08-20 (d) item 4).

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

Report per §8 levels, and per §7.4 report the test count. **Before quoting a count,
run `git status --short`** — if another session's uncommitted work is in the tree,
measure in a `git worktree --detach` or say you could not exclude it. This exact
contamination happened on 2026-08-20 (`HANDOFF.md` 3e).

Any guard or assertion you add or change needs a **positive control**: show it going
red when it should, not only green when it should.

`Arch.md` §14 at the end: "Ready for review", never "done".
```
