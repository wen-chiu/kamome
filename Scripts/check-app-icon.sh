#!/usr/bin/env bash
# The App Store icon carries no alpha channel.
#
# App Store Connect refuses an upload whose 1024 px icon "can't be transparent
# nor contain an alpha channel" (ITMS-90717) — the channel alone is enough, even
# when every pixel is opaque. The icon shipped from 2026-07-16 to 2026-09-30 as
# RGBA with every pixel opaque, and nothing noticed: the build, the tests and
# the simulator are all indifferent. Found by the launch review of 2026-09-30.
#
# Reads the PNG colour type straight from the IHDR chunk (byte 25), so it needs
# no image tool and runs on any machine: 0 = greyscale, 2 = RGB are accepted;
# 4 and 6 carry alpha, and 3 (palette) can carry transparency through tRNS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

iconset=App/Resources/Assets.xcassets/AppIcon.appiconset
failed=0
found=0
while IFS= read -r png; do
  found=$((found + 1))
  colour_type=$(od -An -tu1 -j25 -N1 "$png" | tr -d ' ')
  case "$colour_type" in
    0 | 2) kamome_ok "$png has no alpha channel" ;;
    *)
      kamome_fail "$png has PNG colour type $colour_type — the App Store icon must have no alpha channel (ITMS-90717). Flatten it onto an opaque background."
      failed=1
      ;;
  esac
done < <(git ls-files "$iconset/*.png")

if [ "$found" -eq 0 ]; then
  kamome_fail "no PNG found in $iconset — the gate would measure nothing"
  exit 1
fi

exit $failed
