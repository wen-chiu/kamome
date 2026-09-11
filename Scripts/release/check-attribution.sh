#!/usr/bin/env bash
# Attribution and the privacy notice are licence and store obligations, not copy.
#
# Geoapify attribution is MANDATORY on the free plan and OpenStreetMap
# attribution is always required (Docs/pre-launch.md). Chiu decided 2026-08-17
# that it lives in the app's interface rather than the rendered film.
#
# VERIFIED 2026-09-02: neither string catalogue contained "Geoapify",
# "OpenStreetMap" or "Powered by", and no privacy string existed either — the
# app has shipped its whole life without the attribution its licence requires,
# and nothing anywhere would have said so.
#
# This gate checks the OBLIGATION, never the wording. Where the attribution sits
# and how the notice is phrased are Chiu's (Docs/release-readiness.md S2, S3).
#
# Release-only, deliberately: it fails today, and turning `main` red for work
# that is scheduled rather than broken would make a red check meaningless again
# (HANDOFF.md, "a red check means something now").
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")/../.."

catalog="App/Resources/Localizable.xcstrings"
missing=()

[ -f "$catalog" ] || { kamome_fail "$catalog is missing"; exit 1; }

grep -q "Geoapify"      "$catalog" || missing+=("Geoapify attribution (mandatory on the free plan)")
grep -q "OpenStreetMap" "$catalog" || missing+=("OpenStreetMap attribution (always required)")
grep -qi "privacy"      "$catalog" || missing+=("a privacy notice string (gates Apple's App Privacy questionnaire)")

# Third-party software licences (ADR 2026-09-12 (c)). A different obligation from
# the attribution above: that is owed for data the app fetches, this for code the
# app contains. Every package Package.resolved pins is linked into Kamome.app —
# GRDB through KamomeCore, MapLibre directly — and both licences require their
# notice reproduced in what ships. VERIFIED 2026-09-12: neither text appeared
# anywhere in the app. Checked per pin, so a dependency cannot be added or bumped
# without its licence coming too:
#   1. the verbatim text at App/Resources/Acknowledgements/<identity>.txt, with
#      its copyright notice;
#   2. one line in UI/About/Acknowledgements.swift naming that identity AND the
#      pinned version — a bump is the moment a licence text can change.
# That the text reaches the built bundle is AcknowledgementsTests' half.
resolved="Package.resolved"
ack_dir="App/Resources/Acknowledgements"
ack_list="UI/About/Acknowledgements.swift"
pins=$(/usr/bin/env python3 -c '
import json, sys
for pin in json.load(open(sys.argv[1]))["pins"]:
    print(pin["identity"], pin["state"].get("version", "(unversioned)"))
' "$resolved") || { kamome_fail "could not read the pins in $resolved"; exit 1; }
[ -n "$pins" ] || { kamome_fail "$resolved pins nothing — a licence check over zero packages is not a pass"; exit 1; }

licences=0
while read -r identity version; do
  licences=$((licences + 1))
  text="$ack_dir/$identity.txt"
  if [ ! -s "$text" ] || ! grep -q "Copyright" "$text"; then
    missing+=("the licence text of $identity, verbatim with its copyright notice, at $text")
  fi
  if ! grep -F "id: \"$identity\"" "$ack_list" 2>/dev/null | grep -qF "version: \"$version\""; then
    missing+=("a line in $ack_list naming $identity at its pinned version $version")
  fi
done <<< "$pins"

if [ ${#missing[@]} -eq 0 ]; then
  kamome_ok "attribution and privacy strings are present in $catalog"
  kamome_ok "all $licences pinned packages carry their licence text and an acknowledgement at the pinned version"
  exit 0
fi

kamome_fail "the app cannot ship without these:"
for item in "${missing[@]}"; do kamome_info "  missing — $item"; done
kamome_info "Docs/release-readiness.md S2, S3. The notice must describe BOTH payloads"
kamome_info "(photo-imported vs recorded) — \"start and end coordinates\" is untrue of each."
kamome_info "Licences: copy the pinned package's LICENSE verbatim — never retype or summarise it."
exit 1
