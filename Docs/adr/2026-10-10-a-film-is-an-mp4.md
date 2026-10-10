# A film is an MP4: GIF export and GIF playback are removed

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** spec v1.7's "GIF is demoted to non-blocking" (2026-07-20), which kept GIF as an optional extra

## Context
The export review of 2026-10-10 (#273, #274) measured `RecapGIFEncoder` on the
desk: appending 600 kept frames raised the process footprint by 30 MB, and
`CGImageDestinationFinalize` then raised it by **+2,591 MB** for a 0.8 MB file
(VERIFIED, macOS `swift test`; INFERRED the same on iOS, which ships the same
ImageIO). That is ≈4.3 MB per kept frame, paid at once after the whole render:
≈3.9 GB for a 60 s film, ≈13 GB for Standard's longest. A phone would kill
Kamome after the user had waited through the export (INFERRED; no GIF was ever
exported on a phone). GIF is also 256 colours, which bands the map and the
photographs, and every place a film is shared to autoplays a muted MP4.

## Decision
Chiu: 「其實我覺得可以拿掉」, then, asked about GIFs already made: remove their
playback too.
- Every export is an MP4. The Format row, `RecapExportFormat`,
  `RecapExporter.exportGIF`, `RecapGIFEncoder`, `export.gif_fps` and
  `export.gif_width_px` are gone.
- A `film` row with `format = 'gif'` (TestFlight builds only) stays: listed,
  shareable, savable to Photos, deletable. The app no longer plays it
  (`AnimatedGIFView` is gone); its screen shows no preview.

## Rejected
- Cap the GIF to a short clip: keeps a second format and a second render path
  for a share target the MP4 already covers.
- A streaming GIF writer of our own: code to own for a format nobody needs.

## Consequences
- The map credit's 10 px floor was set by the GIF's 1080 → 480 downscale. It is
  now held at the film's own size; `fontPx` 24 is unchanged, and the headroom
  Chiu asked about on 2026-09-13 now exists.
- `RecapRenderLoop.renderFrames(only:)` stays: the tile bench samples with it.
