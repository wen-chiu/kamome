#!/usr/bin/env bash
# Every soundtrack manifest is one the app would accept, and the app's bundled
# music is exactly its catalog (Docs/handoff-music-in-the-film.md §4.3, §5).
#
# A manifest is written at the desk by Tools/kamome-beatmap.py (through
# Tools/kamome-soundtrack-catalog.py for the bundle) and decoded on the phone by
# SoundtrackManifest.swift. This gate checks every committed one by the same
# rules, stdlib only — librosa is a desk tool and never runs here.
#
# Its own self-test: each file in Tests/Fixtures/soundtracks/invalid/ names the
# refusal it must draw ("_expect"), and SoundtrackManifestTests asks the Swift
# validator for the same code. If the two validators drift apart, one side
# fails.
#
# Audio is bundled, not downloaded (Chiu 2026-11-03, ADR
# 2026-11-03-the-film-chooses-its-music-and-plays-it-on-silent), so audio may be
# committed — but only as App/Resources/Soundtracks/<id>.m4a, each listed in
# SoundtrackCatalog.json with its manifest beside it. Anything else is a file
# the app would carry and never play, or play without a beatmap.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

audio=$(git ls-files | grep -iE '\.(m4a|wav|mp3|aac|flac|caf|aiff?|ogg)$' | grep -vE '^App/Resources/Soundtracks/[^/]+\.m4a$' || true)
if [ -n "$audio" ]; then
  kamome_fail "audio is committed outside App/Resources/Soundtracks/<id>.m4a:"
  printf '%s\n' "$audio" | while read -r f; do kamome_info "  $f"; done
  exit 1
fi

/usr/bin/env python3 - <<'PY'
import glob, json, os, sys
sys.path.insert(0, "Tools")
import kamome_soundtrack_manifest as manifests

limit = manifests.limits()
status = 0
BUNDLE = "App/Resources/Soundtracks"
CATALOG = os.path.join(BUNDLE, "SoundtrackCatalog.json")
bundled = sorted(p for p in glob.glob(BUNDLE + "/*.json") if p != CATALOG)
valid = sorted(glob.glob("Tests/Fixtures/soundtracks/*.json")) + bundled

# The bundle is its catalog: every listed id has a manifest and its audio, and
# nothing sits there unlisted.
tracks = json.load(open(CATALOG))["tracks"] if os.path.exists(CATALOG) else []
if not tracks:
    print("  \033[31mFAIL\033[0m  %s lists no tracks — every film would be silent" % CATALOG, file=sys.stderr)
    status = 1
present = {os.path.basename(p) for p in glob.glob(BUNDLE + "/*") if p != CATALOG}
for track in tracks:
    for name in (track + ".json", track + ".m4a"):
        if name not in present:
            print("  \033[31mFAIL\033[0m  %s lists %s, but %s is missing" % (CATALOG, track, name), file=sys.stderr)
            status = 1
for name in sorted(present - {t + ext for t in tracks for ext in (".json", ".m4a")}):
    print("  \033[31mFAIL\033[0m  %s/%s is not in the catalog" % (BUNDLE, name), file=sys.stderr)
    status = 1
for path in bundled:
    manifest = json.load(open(path))
    track = os.path.splitext(os.path.basename(path))[0]
    if manifest.get("id") != track or manifest.get("file") != track + ".m4a":
        print("  \033[31mFAIL\033[0m  %s: id and file must be %s and %s.m4a" % (path, track, track), file=sys.stderr)
        status = 1
for path in valid:
    try:
        manifests.validate(json.load(open(path)), limit)
    except manifests.Refused as refusal:
        print("  \033[31mFAIL\033[0m  %s: %s" % (path, refusal), file=sys.stderr)
        status = 1

invalid = sorted(glob.glob("Tests/Fixtures/soundtracks/invalid/*.json"))
for path in invalid:
    manifest = json.load(open(path))
    expected = manifest.get("_expect")
    try:
        manifests.validate(manifest, limit)
        got = None
    except manifests.Refused as refusal:
        got = refusal.code
    if got != expected:
        print("  \033[31mFAIL\033[0m  %s should be refused as %s, got %s" % (path, expected, got), file=sys.stderr)
        status = 1

if not valid or not invalid:
    print("  \033[31mFAIL\033[0m  no manifests found — the gate would be checking nothing", file=sys.stderr)
    status = 1
if status == 0:
    print("  \033[32mok\033[0m    %d soundtrack manifest(s) valid, %d refused as each expects, %d bundled tracks = the catalog"
          % (len(valid), len(invalid), len(tracks)))
sys.exit(status)
PY
