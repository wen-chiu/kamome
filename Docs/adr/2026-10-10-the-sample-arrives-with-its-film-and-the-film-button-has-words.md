# The sample arrives with its film made, and the film button says what it does

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** nothing. Amends ADR 2026-09-28-sample-trip ("Entry")

## Context
A first-time-user walk on the simulator (2026-10-10, #285) followed 「先看一支範例影片」:
- VERIFIED: the button opened Trip Detail, with a map and five stops and no film anywhere on the screen.
- VERIFIED: the only way to the film was an unlabelled film-strip icon beside the edit pencil.
- VERIFIED: that icon opened a settings form, and the export then rendered for 213.5 s before anything played.
- UNKNOWN: the time on a phone. One export of the sample on the phone settles it.

The button promised a film and delivered a form and a wait. The same unlabelled icon was the only film entry on every trip.

## Decision
Chiu: 「P0 的先直接修」.
- **The sample ships with its film, one per app language.**
  - The films are `App/Resources/SampleTrip/sample-film-{en,zh-Hant}.mp4`: this app's own export of this trip, re-encoded to HEVC at about 6 MB each (`Scripts/encode-sample-film.sh`).
  - Chiu first kept Chinese only (「App 變大 12 M 有點多」). Told that a reviewer's device is usually English, the same day: 「還是把英文版的範例影片加回去吧」.
  - A language without a film opens the sample without one. It never plays another language's film beside its own stop names.
  - The manifest's `film` entry names the files and the facts their row carries.
- **The button plays it.** `SampleTrip.attachFilm` copies the bundled file into `Films/` and writes a `FilmRecord`; Home then opens the trip with that film playing.
  - The film is stored like any other: it saves, shares and deletes the same way, and a new export from the sample still renders from scratch.
  - Its row has no render time, because nothing was rendered on this phone.
  - If the film cannot be attached, the trip still opens, and the failure is logged.
- **Trip Detail's film entry is a labelled button at the foot of the screen**, 「製作旅程影片」 (Chiu's wording, 2026-10-10) / "Make this a Film" (`make_film`).
  - It has the same weight as Home's import button.
  - It is disabled under the same conditions the icon was.
  - The toolbar keeps only the edit menu.

## Rejected
- **Auto-starting the export when the sample opens:** it is still a multi-minute wait for a film the person asked to *see*.
- **Shipping the exports as they are (H.264, 36 MB each):** 72 MB added to the app for one sample.
- **Chinese only (6 MB):** an English-language reviewer would get the multi-minute render (INFERRED: review devices are usually English).
- **Playing the Chinese film in an English app:** a Chinese title beside English stop names reads as broken.

## Consequences
- The app grows by about 12 MB.
- The bundled films go stale when the film's look changes. Re-render both with the script; `SampleTripTests` only checks that both files exist.
- The App Store review note (A4, #126) is true in both languages as written: "tap *See a sample film first*".
