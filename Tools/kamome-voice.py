#!/usr/bin/env python3
"""Desk only: voice-over and captions for Kamome promo videos, on this Mac.

    ~/Kamome-promo/venv/bin/python Tools/kamome-voice.py say script.txt --lang zh
        → ~/Kamome-promo/footage/voice/script.wav, one line of the script per
          sentence, with a pause between lines, and captions/script.srt timed
          from the audio itself (exact text, no transcription)
    ~/Kamome-promo/venv/bin/python Tools/kamome-voice.py captions some.wav|some.mp4
        → ~/Kamome-promo/captions/some.whisper.srt (for recorded speech;
          a voice-over made by `say` already has exact captions)

Run `Tools/kamome-promo.sh setup` first. Kokoro-82M (Apache-2.0) speaks;
Whisper large-v3-turbo (MIT) transcribes. Both run locally through MLX; the
first run of each downloads its weights from Hugging Face. Scripts and output
stay under ~/Kamome-promo/, never in the repository: a script about a real trip
names real places.

Kokoro reads Latin words in a Chinese line badly: write 卡摸咩 for Kamome there.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(os.environ.get("KAMOME_PROMO_DIR", Path.home() / "Kamome-promo"))
TTS_MODEL = os.environ.get("KAMOME_TTS_MODEL", "mlx-community/Kokoro-82M-bf16")
STT_MODEL = os.environ.get("KAMOME_STT_MODEL", "mlx-community/whisper-large-v3-turbo")
# Kokoro's language codes and a default voice for each; any Kokoro voice works.
LANGS = {"zh": ("z", "zf_xiaobei"), "en": ("a", "af_heart"), "ja": ("j", "jf_alpha")}


def say(args):
    import numpy as np
    import soundfile as sf
    from mlx_audio.tts.utils import load_model

    lang, voice = LANGS[args.lang]
    voice = args.voice or voice
    lines = [l.strip() for l in Path(args.script).read_text(encoding="utf-8").splitlines() if l.strip()]
    if not lines:
        sys.exit("the script is empty")
    model = load_model(TTS_MODEL)
    rate = model.sample_rate
    gap = np.zeros(int(rate * args.pause), dtype=np.float32)
    pieces, cues, at = [], [], 0.0
    for line in lines:
        audio = np.concatenate([np.array(r.audio, dtype=np.float32)
                                for r in model.generate(text=line, voice=voice, speed=args.speed, lang_code=lang)])
        length = len(audio) / rate
        print(f"{length:5.2f} s  {line}")
        cues.append((at, at + length, line))
        at += length + args.pause
        pieces += [audio, gap]
    stem = Path(args.script).stem
    out = ROOT / "footage" / "voice" / (stem + ".wav")
    out.parent.mkdir(parents=True, exist_ok=True)
    sf.write(out, np.concatenate(pieces[:-1]), rate)
    write_srt(ROOT / "captions" / (stem + ".srt"), cues)
    # The same cues for the Remotion template's `voiceCaptions` prop.
    cue_json = ROOT / "captions" / (stem + ".cues.json")
    cue_json.write_text(json.dumps([{"fromS": round(a, 3), "toS": round(b, 3), "text": t} for a, b, t in cues],
                                   ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"→ {cue_json}")
    print(f"→ {out}")


def stamp(s):
    ms = int(round(s * 1000))
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02},{ms % 1000:03}"


def write_srt(path, cues):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for i, (start, end, text) in enumerate(cues, 1):
            f.write(f"{i}\n{stamp(start)} --> {stamp(end)}\n{text}\n\n")
    print(f"→ {path}")


def captions(args):
    import mlx_whisper

    src = Path(args.media)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "audio.wav"  # Whisper wants 16 kHz mono; ffmpeg reads a video too
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(src), "-ac", "1", "-ar", "16000", str(wav)], check=True)
        # The prompt steers spelling: Whisper writes Simplified Chinese and hears
        # "Kamome" as something else unless it is shown both first.
        result = mlx_whisper.transcribe(str(wav), path_or_hf_repo=STT_MODEL, language=args.lang,
                                        initial_prompt=args.prompt, word_timestamps=False)
    cues = [(seg["start"], seg["end"], seg["text"].strip()) for seg in result["segments"]]
    for start, _, text in cues:
        print(f"{stamp(start)}  {text}")
    # Its own name, so it never replaces the exact captions `say` wrote.
    write_srt(ROOT / "captions" / (src.stem + ".whisper.srt"), cues)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("say", help="a script file, one sentence per line → one voice-over wav")
    s.add_argument("script")
    s.add_argument("--lang", choices=LANGS, default="zh")
    s.add_argument("--voice", help="a Kokoro voice name, e.g. zm_yunxi, af_heart")
    s.add_argument("--speed", type=float, default=1.0)
    s.add_argument("--pause", type=float, default=0.45, help="seconds between lines")
    c = sub.add_parser("captions", help="an audio or video file → an .srt")
    c.add_argument("media")
    c.add_argument("--lang", default=None, help="zh, en, ja … (default: detect)")
    c.add_argument("--prompt", default="Kamome 卡摸咩。這是一段繁體中文的旅行影片旁白。",
                   help="spelling hints for Whisper: names, script, style")
    args = p.parse_args()
    {"say": say, "captions": captions}[args.cmd](args)


if __name__ == "__main__":
    main()
