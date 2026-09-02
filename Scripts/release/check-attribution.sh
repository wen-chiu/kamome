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

if [ ${#missing[@]} -eq 0 ]; then
  kamome_ok "attribution and privacy strings are present in $catalog"
  exit 0
fi

kamome_fail "the app cannot ship without these strings:"
for item in "${missing[@]}"; do kamome_info "  missing — $item"; done
kamome_info "Docs/release-readiness.md S2, S3. The notice must describe BOTH payloads"
kamome_info "(photo-imported vs recorded) — \"start and end coordinates\" is untrue of each."
exit 1
