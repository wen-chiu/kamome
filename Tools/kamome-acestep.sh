#!/usr/bin/env bash
# Desk only: install and run ACE-Step 1.5 (MIT) on a Mac, outside this repository,
# for the film-music experiment in Docs/handoff-music-rethink.md (Part D).
#
#   Tools/kamome-acestep.sh setup   # once: uv, a pinned clone, its Python env (~5 GB)
#   Tools/kamome-acestep.sh serve   # the local API on 127.0.0.1:8001; the first run
#                                   # downloads the weights from Hugging Face (~10 GB)
#
# Then, in a second terminal: python3 Tools/kamome-acestep.py generate
#
# Nothing here enters the repository: the clone, the weights and every generated
# file live under ~/Kamome-music/. No trip data is involved at any point.
set -euo pipefail

ACE_URL="https://github.com/ACE-Step/ACE-Step-1.5.git"
# Pinned so the shipped tracks' provenance is reproducible (main, 2026-08-29).
ACE_COMMIT="ca1e85fe9430179831e6bc6be790c332190a3866"
ROOT="${KAMOME_MUSIC_DIR:-$HOME/Kamome-music}"
ACE_DIR="$ROOT/ace-step"
PORT="${ACESTEP_PORT:-8001}"
# Turbo DiT (8 steps) by default; the 1.7B planner gives better structure than the
# 0.6B default when the Mac has ≥ 24 GB of memory. Override either per run.
DIT="${ACESTEP_CONFIG_PATH:-acestep-v15-turbo}"
LM="${ACESTEP_LM_MODEL_PATH:-acestep-5Hz-lm-1.7B}"

die() { printf 'kamome-acestep: %s\n' "$*" >&2; exit 1; }

need_mac() {
  [ "$(uname)" = "Darwin" ] || die "this is for a Mac (Apple Silicon); a Linux box with an NVIDIA GPU can follow ACE-Step's own README"
  [ "$(uname -m)" = "arm64" ] || printf 'warning: not Apple Silicon — no MLX, generation will be slow\n' >&2
}

setup() {
  need_mac
  command -v git >/dev/null || die "git is missing (xcode-select --install)"
  if ! command -v uv >/dev/null; then
    die "uv is missing. Install it first (https://docs.astral.sh/uv/): brew install uv"
  fi
  mkdir -p "$ROOT"
  if [ ! -d "$ACE_DIR/.git" ]; then
    git clone --quiet "$ACE_URL" "$ACE_DIR"
  fi
  git -C "$ACE_DIR" fetch --quiet origin "$ACE_COMMIT" 2>/dev/null || git -C "$ACE_DIR" fetch --quiet origin
  git -C "$ACE_DIR" checkout --quiet "$ACE_COMMIT"
  [ "$(git -C "$ACE_DIR" rev-parse HEAD)" = "$ACE_COMMIT" ] || die "could not check out $ACE_COMMIT"
  head -1 "$ACE_DIR/LICENSE" | grep -q "MIT License" || die "ACE-Step's LICENSE is no longer MIT — stop and tell Chiu"
  (cd "$ACE_DIR" && uv sync)
  printf '\nready: %s at %s\nnext:  Tools/kamome-acestep.sh serve\n' "$ACE_DIR" "${ACE_COMMIT:0:7}"
}

serve() {
  need_mac
  [ -d "$ACE_DIR/.git" ] || die "run 'Tools/kamome-acestep.sh setup' first"
  [ "$(git -C "$ACE_DIR" rev-parse HEAD)" = "$ACE_COMMIT" ] || die "$ACE_DIR is not at the pinned commit; re-run setup"
  printf 'ACE-Step API on http://127.0.0.1:%s  (DiT %s, LM %s)\n' "$PORT" "$DIT" "$LM"
  printf 'The first start downloads the weights; leave it running and use a second terminal.\n\n'
  cd "$ACE_DIR"
  # Local only (127.0.0.1); the MLX backend for the planner on Apple Silicon.
  ACESTEP_LM_BACKEND=mlx TOKENIZERS_PARALLELISM=false ACESTEP_INIT_LLM=true \
    ACESTEP_CONFIG_PATH="$DIT" ACESTEP_LM_MODEL_PATH="$LM" \
    exec uv run acestep-api --host 127.0.0.1 --port "$PORT" --lm-model-path "$LM"
}

case "${1:-}" in
  setup) setup ;;
  serve) serve ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
