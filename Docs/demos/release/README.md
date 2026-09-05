# Release-gate artifacts

Evidence for rows in `Docs/release-readiness.md` that a gate cannot produce.

**All captures below were retaken 2026-09-06** on iPhone 17 Pro Max, iOS 26.5,
from the Debug build — so the debug wrench in the toolbar is present and does
**not** ship. The earlier 2026-09-02 set was replaced rather than kept: the
privacy copy changed that day, and a screenshot that contradicts the code is
worse evidence than none.

⚠️ **Verify the bundle before believing a capture.** These are simulator shots,
and another session building the same bundle id onto the same simulator replaces
the app under you — it happened once during this session and produced a
convincing screenshot of the *previous* wording. Check the installed bundle, not
the source:

    APP=$(xcrun simctl get_app_container <udid> com.chiu.kamome.dev app)
    plutil -extract privacy_hop_relay raw -o - "$APP/en.lproj/Localizable.strings"

## `about-screen-*.png` — S2 and S3

`Scripts/release/check-attribution.sh` proves the strings are **in the
catalogue**. It cannot prove a user can ever **see** them, and that gap is
deliberate: the licence obligation is that the attribution is displayed, not
that it is compiled. These are that half.

| file | what it shows |
|---|---|
| `about-screen-en.png` | `en`: both attributions with their links, the lead, the hop, and what the relay is |
| `about-screen-en-2.png` | the rest of `en`: both payloads, retention, the album control, sharing |
| `about-screen-zh-Hant.png` | the same sheet in `zh-Hant`, the development language |
| `about-screen-zh-Hant-2.png` | the rest of `zh-Hant` |

Reproduce with:

    xcrun simctl launch <udid> com.chiu.kamome.dev -AppleLanguages '(en)' -AppleLocale en_US

⚠️ **Both languages are captured on purpose.** `Powered by Geoapify` is the
format the free plan requires and is therefore **not translated**; a screenshot
of one language would not show that, and a translation pass that "fixed" it
would break the obligation while looking like an improvement.

⚠️ **`250 metres` / `100 per leg` are read from `Config/TrackingConfig.json`,
not typed into the copy.** If a future capture shows different numbers, the
config moved and the notice followed it — which is the intended behaviour, not
a stale screenshot.

## `first-run-notice-*.png` — the S3 answer

ADR 2026-09-05: the user is **told once, on first run**, that real trip
coordinates leave the device. The unit tests prove the gating and the
remembering; they cannot prove anyone can read the screen.

**The card is three lines** (ADR addendum 2026-09-06 — Chiu, on the first
render: *「告知內容的廢話太多了，使用者根本不會看」*). The detail it does not
carry is on the About sheet above, which is what its last line points at.

| file | what it shows |
|---|---|
| `first-run-notice-en.png` | the whole card in `en`: the lead, the hop, where to read the rest, one button |
| `first-run-notice-zh-Hant.png` | the same card in `zh-Hant` |
| `first-run-notice-relaunch-en.png` | **after "Got it", terminate, relaunch** — Home, no notice. The `info.circle` is how it is read again |

⚠️ **Captured against a *simulated* post-flip build, and the repository's config
was not touched.** The notice is silent while `matching.base_url` is `""`, so the
copy of the built `.app` used for these had its **bundled** `TrackingConfig.json`
set to `base_url = https://kamome-routing.invalid` and `api_key_required = false`
— the state the config flip will create. `Config/TrackingConfig.json` is
unchanged and the gate still reads `""`. Reproduce:

    cp -R <DerivedData>/Build/Products/Debug-iphonesimulator/Kamome.app /tmp/cap/
    # edit /tmp/cap/Kamome.app/TrackingConfig.json: base_url, api_key_required
    xcrun simctl install <udid> /tmp/cap/Kamome.app

⚠️ **`api_key_required = false` is what selects the sentence naming the relay**
(`privacy_hop_relay`), and it is also what makes the About sheet show what the
relay is. A capture made with it `true` would show `privacy_hop_direct` and no
relay paragraph — that is the copy following the config, not a stale screenshot.

**No location data is in any of these images** (§0): the device holds no trips.
