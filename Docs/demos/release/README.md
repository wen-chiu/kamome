# Release-gate artifacts

Evidence for rows in `Docs/release-readiness.md` that a gate cannot produce.

## `about-screen-*.png` — S2 and S3, 2026-09-02

`Scripts/release/check-attribution.sh` proves the strings are **in the
catalogue**. It cannot prove a user can ever **see** them, and that gap is
deliberate: the licence obligation is that the attribution is displayed, not
that it is compiled. These are that half.

| file | what it shows |
|---|---|
| `about-screen-en.png` | the sheet in `en`: both attributions with their links, and the first payload |
| `about-screen-en-2.png` | the rest of `en`: the recorded payload, retention, the album control, sharing |
| `about-screen-zh-Hant.png` | the same sheet in `zh-Hant`, the development language |

Captured on iPhone 17 Pro Max, iOS 26.5, from the Debug build — so the debug
wrench in the toolbar is present and does **not** ship. Reproduce with:

    xcrun simctl launch <udid> com.chiu.kamome.dev -AppleLanguages '(en)' -AppleLocale en_US

⚠️ **Both languages are captured on purpose.** `Powered by Geoapify` is the
format the free plan requires and is therefore **not translated**; a screenshot
of one language would not show that, and a translation pass that "fixed" it
would break the obligation while looking like an improvement.

⚠️ **`250 metres` / `100 per leg` are read from `Config/TrackingConfig.json`,
not typed into the copy.** If a future capture shows different numbers, the
config moved and the notice followed it — which is the intended behaviour, not
a stale screenshot.

**No location data is in these images** (§0): the device holds no trips, so the
sheet is the only thing on screen.
