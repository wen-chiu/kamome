#!/usr/bin/env bash
# Desk only: install Stable Audio 3 (Apple Silicon, MLX) outside this repository,
# for the film-music experiment in Docs/handoff-music-rethink.md (Part D).
#
#   Tools/kamome-stableaudio.sh setup     # once: pinned clone, MLX env, weights (~6 GB),
#                                         # the weights' licence checked and kept,
#                                         # and the Community License registration recorded
#   Tools/kamome-stableaudio.sh licence   # show what was recorded
#
# Then: python3 Tools/kamome-stableaudio.py generate
#
# Commercial use of these weights is under the Stability AI Community License:
# free below US$1,000,000 annual revenue (Kamome together with its affiliates),
# and ONLY after registering at https://stability.ai/community-license.
# This script refuses to finish until that registration is recorded.
set -euo pipefail

SA3_URL="https://github.com/Stability-AI/stable-audio-3.git"
# Pinned so the shipped tracks' provenance is reproducible (main, 2026-10-30).
SA3_COMMIT="5f5e6ac21ae9ff78a6e8847eb7a1dcbe969ffb84"
WEIGHTS_REPO="stabilityai/stable-audio-3-optimized"
ROOT="${KAMOME_MUSIC_DIR:-$HOME/Kamome-music}"
SA3_DIR="$ROOT/stable-audio-3"
MLX_DIR="$SA3_DIR/optimized/mlx"
RECORD="$SA3_DIR/kamome-licence.json"
REGISTER_URL="https://stability.ai/community-license"

die() { printf 'kamome-stableaudio: %s\n' "$*" >&2; exit 1; }

need_mac() {
  [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] ||
    die "the MLX route needs an Apple Silicon Mac"
}

# The weights' own licence file, fetched from the weights repository and checked
# for the terms Kamome relies on. A changed licence stops the setup.
check_weights_licence() {
  "$MLX_DIR/.venv/bin/python" -I - "$WEIGHTS_REPO" "$SA3_DIR" <<'PY'
import hashlib, os, shutil, sys
from huggingface_hub import hf_hub_download, list_repo_files
repo, dest = sys.argv[1], sys.argv[2]
names = [f for f in list_repo_files(repo) if os.path.basename(f).upper().startswith(('LICENSE', 'NOTICE'))]
if not names:
    sys.exit(f'no LICENSE file in {repo}: stop and tell Chiu')
kept = []
for name in names:
    path = hf_hub_download(repo_id=repo, filename=name)
    out = os.path.join(dest, 'weights-' + os.path.basename(name))
    shutil.copyfile(path, out)
    kept.append((name, out, hashlib.sha256(open(out, 'rb').read()).hexdigest()))
text = ' '.join(open(o, encoding='utf-8', errors='replace').read() for _, o, _ in kept).upper()
need = {'STABILITY AI COMMUNITY LICENSE': 'the Community License',
        '1,000,000': 'the US$1,000,000 revenue threshold',
        'YOU OWN ANY OUTPUTS': 'output ownership'}
missing = [why for key, why in need.items() if key not in ' '.join(text.split())]
if missing:
    sys.exit('the weights licence no longer states ' + ', '.join(missing) +
             ': stop and tell Chiu before generating anything for Kamome')
for name, out, digest in kept:
    print(f'{name}\t{out}\tsha256:{digest}')
PY
}

setup() {
  need_mac
  command -v git >/dev/null || die "git is missing (xcode-select --install)"
  mkdir -p "$ROOT"
  if [ ! -d "$SA3_DIR/.git" ]; then
    git clone --quiet "$SA3_URL" "$SA3_DIR"
  fi
  git -C "$SA3_DIR" fetch --quiet origin "$SA3_COMMIT" 2>/dev/null || git -C "$SA3_DIR" fetch --quiet origin
  git -C "$SA3_DIR" checkout --quiet "$SA3_COMMIT"
  [ "$(git -C "$SA3_DIR" rev-parse HEAD)" = "$SA3_COMMIT" ] || die "could not check out $SA3_COMMIT"
  head -1 "$SA3_DIR/LICENSE" | grep -q "MIT License" || die "the code's LICENSE is no longer MIT — stop and tell Chiu"

  # Medium (1.4 B, higher quality) and small-music (fast), each with its decoder,
  # plus the shared T5Gemma text encoder.
  (cd "$MLX_DIR" && ./install.sh -y --download medium,sm-music)

  printf '\nChecking the weights licence in %s …\n' "$WEIGHTS_REPO"
  local files
  files="$(check_weights_licence)" || die "weights licence check failed (see above)"
  printf '%s\n' "$files"

  if [ -f "$RECORD" ]; then
    printf '\nRegistration already recorded:\n'; cat "$RECORD"; printf '\n'
  else
    cat <<EOF

────────────────────────────────────────────────────────────────────────────
Commercial use needs a one-time registration with Stability AI (free):
  1. Open $REGISTER_URL and register Kamome
     (as the person or company that will publish the app).
  2. Confirm that you and your affiliates earn under US\$1,000,000 a year.
     If that is ever exceeded, the licence ends and an Enterprise licence is needed.
  3. Generate on your own Mac, for Kamome — not for or on an employer's behalf,
     whose revenue would count instead.
────────────────────────────────────────────────────────────────────────────
EOF
    local ans who
    read -r -p "Have you registered at $REGISTER_URL? [y/N] " ans
    case "$ans" in y|Y|yes|YES) ;; *) die "not recorded. Register, then run setup again." ;; esac
    read -r -p "Registered as (your name or company): " who
    [ -n "$who" ] || die "a registrant is needed"
    "$MLX_DIR/.venv/bin/python" -I - "$RECORD" "$who" "$REGISTER_URL" "$SA3_COMMIT" "$files" <<'PY'
import json, sys, datetime
record, who, url, commit, files = sys.argv[1:6]
json.dump({
    'licence': 'Stability AI Community License',
    'registered_at': url,
    'registrant': who,
    'recorded_on': datetime.date.today().isoformat(),
    'revenue_under_usd_1m_confirmed': True,
    'stable_audio_3_commit': commit,
    'weights_licence_files': [dict(zip(('name', 'copy', 'sha256'), l.split('\t'))) for l in files.splitlines()],
}, open(record, 'w'), ensure_ascii=False, indent=1)
PY
    printf '\nrecorded: %s\n' "$RECORD"
  fi
  printf 'next: python3 Tools/kamome-stableaudio.py generate --only tropical --mood depart --takes 1\n'
}

case "${1:-}" in
  setup) setup ;;
  licence|license) [ -f "$RECORD" ] && cat "$RECORD" || die "nothing recorded; run setup" ;;
  *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
