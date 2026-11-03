#!/usr/bin/env bash
# Desk only: the local toolkit for Kamome's marketing and demo videos.
#
#   Tools/kamome-promo.sh setup   # once: Node 22, a Remotion project, a Python env for
#                                 # voice-over (Kokoro) and captions (Whisper), and the
#                                 # Real-ESRGAN / RIFE binaries (~3 GB with weights)
#   Tools/kamome-promo.sh check   # each tool answers, nothing is generated
#   Tools/kamome-promo.sh upscale <in> <out>   # 4× Real-ESRGAN: a photo, a folder of
#                                 # photos (names kept) or a video (audio kept).
#                                 # ~2.5 s a frame on an M2: photos, not long videos
#   Tools/kamome-promo.sh smooth <in.mp4> <out.mp4>   # RIFE: twice the frame rate.
#                                 # Look at the result: it invents in-between
#                                 # frames and smears text and map labels.
#
# Nothing here enters the repository: every tool, weight and generated file lives
# under ~/Kamome-promo/. Every tool runs on this Mac; nothing is uploaded. Footage
# comes from the app itself (App Store previews may show only captures of the app).
set -euo pipefail

# An Intel Homebrew bash runs under Rosetta, and MLX would then refuse to load:
# re-run natively with the system bash.
if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
  exec arch -arm64 /bin/bash "$0" "$@"
fi

ROOT="${KAMOME_PROMO_DIR:-$HOME/Kamome-promo}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/promo"
NODE_MAJOR=22
REMOTION_VERSION="4.0.540"
PYTHON_VERSION="3.12"
MLX_AUDIO_VERSION="0.6.4"
MLX_WHISPER_VERSION="0.4.3"
ESRGAN_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
RIFE_URL="https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-macos.zip"
# Weights, fetched from Hugging Face on first use: Kokoro-82M (Apache-2.0) and
# Whisper large-v3-turbo (MIT).
TTS_MODEL="${KAMOME_TTS_MODEL:-mlx-community/Kokoro-82M-bf16}"
STT_MODEL="${KAMOME_STT_MODEL:-mlx-community/whisper-large-v3-turbo}"

die() { printf 'kamome-promo: %s\n' "$*" >&2; exit 1; }

need_mac() {
  [ "$(uname)" = "Darwin" ] || die "this is for a Mac (Apple Silicon)"
  [ "$(uname -m)" = "arm64" ] || die "MLX needs Apple Silicon"
}

use_node() {
  # shellcheck disable=SC1091
  . "${NVM_DIR:-$HOME/.nvm}/nvm.sh" || die "nvm is missing (https://github.com/nvm-sh/nvm)"
  nvm use --silent "$NODE_MAJOR" >/dev/null 2>&1 || nvm install "$NODE_MAJOR" >/dev/null
  nvm use --silent "$NODE_MAJOR" >/dev/null
}

fetch_zip() { # url dir
  local url="$1" dir="$2" zip
  [ -d "$dir" ] && return 0
  zip="$ROOT/bin/$(basename "$url")"
  curl -fL --retry 5 -C - --progress-bar -o "$zip" "$url"
  # Some zips hold one folder, some hold loose files: unpack aside, then place.
  local tmp="$ROOT/bin/.unpack"
  rm -rf "$tmp" && ditto -x -k "$zip" "$tmp"
  rm -f "$zip"
  local inner=("$tmp"/*)
  if [ "${#inner[@]}" -eq 1 ] && [ -d "${inner[0]}" ]; then mv "${inner[0]}" "$dir"; else mv "$tmp" "$dir"; fi
  rm -rf "$tmp"
  [ -d "$dir" ] || die "$(basename "$url") did not unpack to $dir"
  xattr -dr com.apple.quarantine "$dir" 2>/dev/null || true
  chmod +x "$dir"/*-ncnn-vulkan
}

setup() {
  need_mac
  command -v uv >/dev/null || die "uv is missing: brew install uv"
  mkdir -p "$ROOT"/{bin,footage,voice,captions,out}

  use_node
  if [ ! -f "$ROOT/remotion/package.json" ]; then
    mkdir -p "$ROOT/remotion"
    (cd "$ROOT/remotion" && npm init -y >/dev/null \
      && npm install --save-exact --no-fund --no-audit \
        "remotion@$REMOTION_VERSION" "@remotion/cli@$REMOTION_VERSION" \
        "@remotion/media-utils@$REMOTION_VERSION" react@19 react-dom@19)
  fi
  # The template is tracked in Tools/promo; the project only links to it.
  for f in src tsconfig.json remotion.config.ts props.example.json; do
    ln -sfn "$TEMPLATE/$f" "$ROOT/remotion/$f"
  done

  if [ ! -x "$ROOT/venv/bin/python" ]; then
    uv venv --quiet --python "$PYTHON_VERSION" "$ROOT/venv"
  fi
  # Long timeouts: torch alone is a large wheel and slow links time out at 30 s.
  UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-900}" VIRTUAL_ENV="$ROOT/venv" uv pip install --quiet \
    "mlx-audio==$MLX_AUDIO_VERSION" "mlx-whisper==$MLX_WHISPER_VERSION" "misaki[zh,ja]" soundfile

  fetch_zip "$ESRGAN_URL" "$ROOT/bin/realesrgan-ncnn-vulkan-20220424-macos"
  fetch_zip "$RIFE_URL" "$ROOT/bin/rife-ncnn-vulkan-20221029-macos"
  printf '\nready: %s\nnext:  Tools/kamome-promo.sh check\n' "$ROOT"
}

check() {
  need_mac
  [ -d "$ROOT/venv" ] || die "run 'Tools/kamome-promo.sh setup' first"
  use_node
  (cd "$ROOT/remotion" && npx --no-install remotion versions >/dev/null) && echo "ok  remotion $REMOTION_VERSION (node $(node -v))"
  "$ROOT/venv/bin/python" -c "import mlx_audio, mlx_whisper" && echo "ok  mlx-audio $MLX_AUDIO_VERSION, mlx-whisper $MLX_WHISPER_VERSION"
  local esr="$ROOT/bin/realesrgan-ncnn-vulkan-20220424-macos/realesrgan-ncnn-vulkan"
  local rife="$ROOT/bin/rife-ncnn-vulkan-20221029-macos/rife-ncnn-vulkan"
  [ -x "$esr" ] && echo "ok  real-esrgan" || echo "MISSING real-esrgan"
  [ -x "$rife" ] && echo "ok  rife" || echo "MISSING rife"
  command -v ffmpeg >/dev/null && echo "ok  ffmpeg $(ffmpeg -version | head -1 | awk '{print $3}') ($(file -b "$(command -v ffmpeg)" | awk '{print $NF}'))"
  echo "tts model: $TTS_MODEL   stt model: $STT_MODEL"
}

ESRGAN_DIR() { echo "$ROOT/bin/realesrgan-ncnn-vulkan-20220424-macos"; }
RIFE_DIR() { echo "$ROOT/bin/rife-ncnn-vulkan-20221029-macos"; }

is_video() { case "$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')" in mp4|mov|m4v) return 0 ;; esac; return 1; }

# Runs an ncnn tool over every frame of a video and puts the audio back.
# usage: per_frame <in> <out> <fps-multiplier> <tool args…>
per_frame() {
  local in="$1" out="$2" mult="$3"; shift 3
  local work fps
  work="$(mktemp -d "$ROOT/out/.frames.XXXX")"
  mkdir -p "$work/in" "$work/out"
  fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$in")"
  ffmpeg -loglevel error -i "$in" "$work/in/%08d.png"
  "$@" -i "$work/in" -o "$work/out" >/dev/null 2>&1 || die "$1 failed on $(basename "$in")"
  ffmpeg -loglevel error -y -framerate "$fps*$mult" -i "$work/out/%08d.png" -i "$in" \
    -map 0:v -map 1:a? -c:v libx264 -crf 16 -pix_fmt yuv420p -c:a copy -shortest "$out"
  rm -rf "$work"
  echo "→ $out"
}

upscale() {
  local in="${1:?usage: upscale <in> <out>}" out="${2:?usage: upscale <in> <out>}" dir
  dir="$(ESRGAN_DIR)"; [ -x "$dir/realesrgan-ncnn-vulkan" ] || die "run setup first"
  in="$(cd "$(dirname "$in")" && pwd)/$(basename "$in")"
  mkdir -p "$(dirname "$out")"; out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
  # The tool finds its models relative to the working directory.
  cd "$dir"
  if is_video "$in"; then per_frame "$in" "$out" 1 ./realesrgan-ncnn-vulkan -n realesrgan-x4plus
  else
    [ -d "$in" ] && mkdir -p "$out"
    ./realesrgan-ncnn-vulkan -n realesrgan-x4plus -i "$in" -o "$out" >/dev/null 2>&1 || die "real-esrgan failed"
    echo "→ $out"
  fi
}

smooth() {
  local in="${1:?usage: smooth <in.mp4> <out.mp4>}" out="${2:?usage: smooth <in.mp4> <out.mp4>}" dir
  dir="$(RIFE_DIR)"; [ -x "$dir/rife-ncnn-vulkan" ] || die "run setup first"
  is_video "$in" || die "smooth takes a video"
  in="$(cd "$(dirname "$in")" && pwd)/$(basename "$in")"
  mkdir -p "$(dirname "$out")"; out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
  cd "$dir"
  per_frame "$in" "$out" 2 ./rife-ncnn-vulkan -m rife-v4.6
}

case "${1:-}" in
  setup) setup ;;
  check) check ;;
  upscale) shift; upscale "$@" ;;
  smooth) shift; smooth "$@" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
