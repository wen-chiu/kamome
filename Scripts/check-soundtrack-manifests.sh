#!/usr/bin/env bash
# Every committed soundtrack manifest is one the app would accept, and no audio
# is committed (Docs/handoff-music-in-the-film.md §5, ADR 2026-11-03).
#
# A manifest is written at the desk by Tools/kamome-beatmap.py and decoded on
# the phone by SoundtrackManifest.swift. This gate checks every committed one by
# the same rules, stdlib only — librosa is a desk tool and never runs here.
#
# Its own self-test: each file in Tests/Fixtures/soundtracks/invalid/ names the
# refusal it must draw ("_expect"), and SoundtrackManifestTests asks the Swift
# validator for the same code. If the two validators drift apart, one side
# fails.
#
# No audio file is tracked while bundle-vs-download is open (handoff §7 item 6):
# real tracks live in ~/Kamome-music, tests synthesise their own.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

audio=$(git ls-files | grep -iE '\.(m4a|wav|mp3|aac|flac|caf|aiff?|ogg)$' || true)
if [ -n "$audio" ]; then
  kamome_fail "audio is committed, and bundle vs download is still Chiu's call:"
  printf '%s\n' "$audio" | while read -r f; do kamome_info "  $f"; done
  exit 1
fi

/usr/bin/env python3 - <<'PY'
import glob, json, os, sys
sys.path.insert(0, "Tools")
import kamome_soundtrack_manifest as manifests

limit = manifests.limits()
status = 0
valid = sorted(glob.glob("Tests/Fixtures/soundtracks/*.json") + glob.glob("App/Resources/Soundtracks/*.json"))
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
    print("  \033[32mok\033[0m    %d soundtrack manifest(s) valid, %d refused as each expects, no audio committed"
          % (len(valid), len(invalid)))
sys.exit(status)
PY
