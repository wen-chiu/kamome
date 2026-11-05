# A trip of one place is refused before the film button

**Status:** Decided (Chiu, 2026-11-04); the sentence's wording is a draft until Chiu settles it
**Supersedes:** nothing

## Context
VERIFIED (desk probe 2026-11-02, #350): a trip whose photographs all carry one location imports, offers 「製作旅程影片」, and the export fails with no film. Import needs only two route points and a leg (`ImportedTripPlan.isRenderable`); the camera refuses a route of no length (`CameraPath`), so there is no `LinearTimeline`; the button checked only that the trip had ended and its film's stops were named. Photographs a metre or a centimetre apart make a 60 s film. INFERRED: the cause in the wild is a location set by hand in Photos (Adjust Location), or one burst.

## Decision
Chiu (#350, 2026-11-04), option 2, for 1.0: "A trip whose photographs all carry one location is refused before the button. 「製作旅程影片」 is disabled, and one sentence on Trip Detail says why: the trip has only one place."

- **The test is the camera's own.** `CameraPath.goesSomewhere` (two vertices or more, some length between them) is what `CameraPath.init` calls to refuse, and Trip Detail asks it of the route the export composes (`RecapComposer.filmGoesSomewhere`, through the same `filmLegs`). Zero is the only cut, so there is no threshold and nothing in `TrackingConfig.json`.
- **The sentence sits above the disabled button.** VoiceOver reads it as text, and the button carries it as its hint, so it is heard either way a person reaches the button.
- **Import still accepts the trip.** Its photographs, stop, map and diary stay on Trip Detail, where the sentence is.

## Rejected
- **Option 1, a film of one place** (title, the stop's photographs, end card, no travel): after 1.0. `CameraPath` still refuses a route of no length.
- **Refusing at import:** the trip and its photographs would not appear in Kamome at all, trips imported before would still reach the button, and the sentence needs a trip to stand on.
- **A distance threshold for "one place"** (such as `discovery.single_place_extent_m`, 60 km, which names a trip by its town): a trip a centimetre across films, so any cut above zero would refuse films that work and contradict the camera.

## Consequences
- `CameraPath.goesSomewhere` is public; `RecapComposer.filmLegs` is shared by the export and the button; `TripDetailModel` holds `filmHasOnePlace` and `canMakeFilm`; the bar is `FilmButtonBar`. Catalogue key `make_film_one_place` (en, zh-Hant).
- The path probe models the button: a trip refused before it is not a violation; a refused trip that has a film plan is, and so is a button whose answer changes once routing answers. D4, D4b and D4c leave its `knownDefects`.
- Home's next-step card can still name a trip of one place; its button opens Trip Detail, where the film sheet does not open (`openPendingFilmSheet` waits on the same rule) and the sentence says why. Whether the card should pass over such a trip is Chiu's.
