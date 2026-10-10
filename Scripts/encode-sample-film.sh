#!/usr/bin/env bash
# Re-encodes an exported sample film for the bundle (#285).
#
# The sample trip ships with its film already made, so 「先看一支範例影片」 plays
# at once instead of after a multi-minute render. Only the Chinese film ships
# (Chiu 2026-10-10: two at 12 MB was too much). An export is H.264 at about
# 5 Mbit/s, 36 MB for the sample's 60 s; HEVC at CRF 28 is about 6 MB and
# keeps the drawings sharp (checked 2026-10-10 on the 三仙台 card at full 1080×1920).
#
# Make the input on the simulator, in the language it is for:
#   1. erase the device (so the vehicle is a new user's default, the red car),
#      install, launch with -AppleLanguages "(zh-Hant-TW)" or "(en)";
#   2. 「先看一支範例影片」 → 「製作旅程影片」 → export;
#   3. take the newest Films/kamome-recap-*.mp4 out of the app container.
# Then:
#   Scripts/encode-sample-film.sh <exported.mp4> zh-Hant
# (`en` still works, should an English film ever ship again: add it to the
# manifest's `film.files` too.)
#
# Needs ffmpeg with libx265 (Homebrew's has it). A desk tool, never part of
# the build. Re-run it whenever the film's look changes, or the bundled film
# is a film the app no longer makes.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <exported.mp4> <en|zh-Hant>" >&2
  exit 2
fi
input=$1
language=$2
case "$language" in
  en|zh-Hant) ;;
  *) echo "language must be en or zh-Hant, got: $language" >&2; exit 2 ;;
esac

output=App/Resources/SampleTrip/sample-film-$language.mp4
# hvc1, not the default hev1, or AVPlayer and Photos refuse the file.
ffmpeg -v error -y -i "$input" -c:v libx265 -crf 28 -preset medium -tag:v hvc1 \
  -an -movflags +faststart "$output"
ls -lh "$output"
