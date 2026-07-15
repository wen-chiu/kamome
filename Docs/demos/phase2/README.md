# Phase 2 demo artifacts (spec §7 gate)

## s3-demo-trip.png

S3 Trip Detail rendering the seeded demo trip (`-demo-seed -demo-open-trip`
launch arguments, iPhone 17 Pro simulator, iOS 26.5):

- Perth → Margaret River route polyline (drive mode, solid)
- 4 stop pins; **Busselton Jetty and Margaret River carry photo-count
  badges (2 each)** — seeded `photo_ref` rows assigned to those stops
- stats strip from `trip.stats_json`: 271 km · 4.8 h driving · 4 stops · 96 km/h
- timeline with reverse-geocode-style names and photo thumbnails; the tiles
  render the §3 graceful-placeholder path (asset ids deliberately dangling —
  `simctl privacy` cannot pre-answer the iOS 26 photos prompt, so the demo
  proves assignment + placeholder handling; live PhotoKit matching is covered
  by unit tests and the on-device manual check)
- one photo marked highlight (star)

## photo-permission-priming.png

The system photos dialog over S3, showing the localized
`NSPhotoLibraryUsageDescription` ("Selected-photos access works too…").
The remaining gate item — the limited-access path — is verified manually on
device: choose "Limit Access…" and confirm matching works with a subset.

Regenerate: build the Kamome scheme, then
`xcrun simctl launch <udid> com.chiu.kamome.dev -demo-seed -demo-open-trip`
on a freshly-installed app and screenshot via `simctl io`.
