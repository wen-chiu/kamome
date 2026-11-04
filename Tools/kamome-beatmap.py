#!/usr/bin/env python3
"""Turn one kept, mastered track into its soundtrack manifest, or refuse it.

    ~/Kamome-music/.beatmap-venv/bin/python Tools/kamome-beatmap.py \\
        ~/Kamome-music/stableaudio/anthem/anthem-depart-s1855554642.wav \\
        --style anthem --mood depart --engine stable-audio-3 --out anthem-depart-s1855554642.json

Docs/handoff-music-in-the-film.md §5. Desk only: librosa is a desk dependency
(Chiu 2026-11-03) and never runs in the app or ./check.sh. The manifest it writes
is the one Core/ExportEngine/SoundtrackManifest.swift decodes, validated by
Tools/kamome_soundtrack_manifest.py before it is written.

What it measures, and what it refuses:
  * Tempo and grid. The brief sets the BPM (Tools/kamome_music_briefs.py);
    librosa tracks the beats and a straight line is fitted through them, so the
    grid is exact across the whole track. Refused when the fit is off the brief
    or the tempo drifts by more than `tempo_drift_max_bpm` anywhere.
  * The first downbeat: the beat phase whose beats carry the most low-end onset.
  * Loudness with `ffmpeg -af ebur128=peak=true`: refused unless within
    `loudness_tolerance_lu` of `target_lufs` with true peak at or under
    `true_peak_max_dbtp` (Config/TrackingConfig.json `soundtrack`).
  * Sections are PROPOSED from the self-similarity of 8-bar chunks and printed
    for Chiu's ear. The manifest says `sections_confirmed: false` until they are
    passed back with --sections ... --confirmed after he has listened.

Stdout carries no trip data — there is none here; a track is not a trip.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kamome_music_briefs as briefs  # noqa: E402
import kamome_soundtrack_manifest as manifests  # noqa: E402

BEATS_PER_BAR = 4  # every brief is 4/4 (kamome_music_briefs: time_signature 4/4)


def refuse(why):
    sys.exit(f'REFUSED: {why}')


def loudness(path):
    """Integrated LUFS and true peak dBTP, as ffmpeg's EBU R128 meter reads them."""
    out = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', path, '-af', 'ebur128=peak=true',
                          '-f', 'null', '-'], capture_output=True, text=True).stderr
    summary = out[out.rfind('Summary:'):]
    integrated = re.search(r'I:\s+(-?[\d.]+) LUFS', summary)
    peak = re.search(r'Peak:\s+(-?[\d.]+|-inf) dBFS', summary)
    if not integrated or not peak:
        refuse(f'ffmpeg could not measure {path}')
    return float(integrated.group(1)), float(peak.group(1))


def grid(y, sr, brief_bpm, librosa, np):
    """A straight line through the tracked beats: (bpm, first beat s, drift)."""
    _, beats = librosa.beat.beat_track(y=y, sr=sr, start_bpm=brief_bpm, units='time', tightness=400)
    if len(beats) < 16:
        refuse('too few beats tracked to fit a grid')
    period = 60.0 / brief_bpm
    index = np.round((beats - beats[0]) / period)
    slope, intercept = np.polyfit(index, beats, 1)
    # Local tempo in 8-bar windows: the most any stretch departs from the line.
    window = 8 * BEATS_PER_BAR
    local = [60.0 / np.polyfit(index[i:i + window], beats[i:i + window], 1)[0]
             for i in range(0, len(beats) - window + 1, window // 2)]
    bpm = 60.0 / slope
    drift = max(abs(b - bpm) for b in local) if local else 0.0
    return bpm, intercept, drift


def first_downbeat(y, sr, beat0, period, librosa, np):
    """The beat phase (of four) carrying the most low-end onset is the downbeat."""
    low = librosa.onset.onset_strength(y=y, sr=sr, fmax=250, n_mels=12)
    times = librosa.times_like(low, sr=sr)
    duration = len(y) / sr
    beat_times = np.arange(beat0, duration, period)
    strength = np.interp(beat_times, times, low)
    phase = int(np.argmax([strength[k::BEATS_PER_BAR].mean() for k in range(BEATS_PER_BAR)]))
    bar = period * BEATS_PER_BAR
    downbeat = beat0 + phase * period
    return downbeat - np.floor(downbeat / bar) * bar


def propose_sections(y, sr, downbeat, bar_s, duration, chunk_bars, librosa, np):
    """8-bar chunks, labelled by self-similarity, ranked by loudness."""
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
    rms = librosa.feature.rms(y=y)[0]
    times = librosa.times_like(rms, sr=sr)
    usable_bars = int((duration - downbeat) // bar_s)
    chunks = []
    for start in range(0, usable_bars, chunk_bars):
        bars = min(chunk_bars, usable_bars - start)
        lo, hi = downbeat + start * bar_s, downbeat + (start + bars) * bar_s
        mask = (times >= lo) & (times < hi)
        feature = np.concatenate([chroma[:, mask].mean(axis=1), mfcc[1:, mask].mean(axis=1) / 50])
        loud = 20 * np.log10(max(rms[mask].mean(), 1e-6))
        chunks.append({'start_bar': start, 'bars': bars, 'feature': feature, 'loud': loud})
    # Standardised across the track, so similarity measures what differs
    # between its chunks rather than what every chunk of one song shares.
    features = np.array([c['feature'] for c in chunks])
    features = (features - features.mean(axis=0)) / (features.std(axis=0) + 1e-9)
    norms = np.linalg.norm(features, axis=1) + 1e-9
    similarity = features @ features.T / np.outer(norms, norms)
    labels = []
    for i in range(len(chunks)):
        best = int(np.argmax(similarity[i, :i])) if i else -1
        labels.append(labels[best] if i and similarity[i, best] > 0.5 else chr(ord('A') + len(set(labels))))
    louds = sorted(c['loud'] for c in chunks)
    for c, label in zip(chunks, labels):
        rank = sum(1 for v in louds if v <= c['loud']) / len(louds)
        c['energy'] = 1 + min(int(rank * 4), 3)
        c['label'] = label
    return chunks


def roles(chunks):
    """intro first, outro last, the loudest repeated material the peak, the
    chunk before a peak its lift, everything else body. A proposal only."""
    top = max(c['energy'] for c in chunks[1:-1]) if len(chunks) > 2 else 0
    sections = []
    for i, c in enumerate(chunks):
        role = ('intro' if i == 0 else 'outro' if i == len(chunks) - 1
                else 'peak' if c['energy'] == top
                else 'lift' if i + 1 < len(chunks) - 1 and chunks[i + 1]['energy'] == top and c['energy'] < top
                else 'body')
        sections.append({'name': f'{role}-{c["label"]}{i}', 'start_bar': c['start_bar'], 'bars': c['bars'],
                         'energy': c['energy'], 'role': role, 'repeatable': role in ('body', 'peak')})
    return sections


def final_hit(y, sr, downbeat, bar_s, outro, librosa, np):
    """The last downbeat inside the outro with a full-strength onset."""
    onset = librosa.onset.onset_strength(y=y, sr=sr)
    times = librosa.times_like(onset, sr=sr)
    bars = range(outro['start_bar'], outro['start_bar'] + outro['bars'] + 1)
    strength = {b: float(np.interp(downbeat + b * bar_s, times, onset)) for b in bars}
    typical = float(np.median(list(strength.values())))
    return max(b for b, s in strength.items() if s >= typical)


def parse_sections(text):
    """name:start:bars:energy:role[:r], comma-separated — Chiu's confirmed list."""
    out = []
    for item in text.split(','):
        name, start, bars, energy, role, *flag = item.strip().split(':')
        out.append({'name': name, 'start_bar': int(start), 'bars': int(bars), 'energy': int(energy),
                    'role': role, 'repeatable': flag == ['r']})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('track')
    ap.add_argument('--style', required=True, choices=list(briefs.STYLES))
    ap.add_argument('--mood', required=True, choices=list(briefs.MOODS))
    ap.add_argument('--engine', required=True, help='e.g. acestep-1.5 or stable-audio-3')
    ap.add_argument('--commit', help='the engine checkout the take came from')
    ap.add_argument('--seed', type=int, help='defaults to the -s<seed> in the file name')
    ap.add_argument('--chunk-bars', type=int, default=8, help='section proposal grain (handoff §5: 8)')
    ap.add_argument('--sections', help='confirmed sections, name:start:bars:energy:role[:r],…')
    ap.add_argument('--final-hit-bar', type=int, help='confirmed final hit bar')
    ap.add_argument('--confirmed', action='store_true', help='Chiu has listened to these sections')
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    import librosa
    import numpy as np

    limit = manifests.limits()
    brief_bpm = briefs.STYLES[args.style][args.mood][0]
    integrated, peak = loudness(args.track)
    if abs(integrated - limit['target_lufs']) > limit['loudness_tolerance_lu']:
        refuse(f'{integrated} LUFS, target {limit["target_lufs"]} ± {limit["loudness_tolerance_lu"]} — master it first')
    if peak > limit['true_peak_max_dbtp']:
        refuse(f'true peak {peak} dBTP, limit {limit["true_peak_max_dbtp"]} — master it first')

    y, sr = librosa.load(args.track, sr=None, mono=True)
    duration = len(y) / sr
    bpm, beat0, drift = grid(y, sr, brief_bpm, librosa, np)
    if abs(bpm - brief_bpm) > limit['tempo_drift_max_bpm']:
        refuse(f'measured {bpm:.2f} BPM, the brief says {brief_bpm}')
    if drift > limit['tempo_drift_max_bpm']:
        refuse(f'the tempo drifts {drift:.2f} BPM across the track')
    bpm = round(bpm, 4)
    bar_s = 60.0 / bpm * BEATS_PER_BAR
    downbeat = round(first_downbeat(y, sr, beat0, 60.0 / bpm, librosa, np), 4)

    chunks = propose_sections(y, sr, downbeat, bar_s, duration, args.chunk_bars, librosa, np)
    sections = parse_sections(args.sections) if args.sections else roles(chunks)
    hit = args.final_hit_bar if args.final_hit_bar is not None else final_hit(
        y, sr, downbeat, bar_s, sections[-1], librosa, np)
    hit_s = downbeat + hit * bar_s
    seed = args.seed
    if seed is None:
        found = re.search(r'-s(\d+)\.', os.path.basename(args.track))
        seed = int(found.group(1)) if found else None
    track_id = os.path.splitext(os.path.basename(args.track))[0]
    manifest = {
        'schema_version': manifests.SCHEMA_VERSION, 'id': track_id, 'style': args.style, 'mood': args.mood,
        'file': track_id + '.m4a', 'duration_s': round(duration, 6), 'bpm': bpm, 'beats_per_bar': BEATS_PER_BAR,
        'first_downbeat_s': downbeat, 'tempo_drift_bpm': round(drift, 4), 'sections': sections,
        'sections_confirmed': bool(args.confirmed and args.sections), 'final_hit_bar': hit,
        'tail_s': math.floor(max(duration - hit_s, 0.0) * 1e4) / 1e4, 'integrated_lufs': integrated,
        'true_peak_dbtp': peak, 'provenance': {'engine': args.engine, 'commit': args.commit, 'seed': seed},
    }
    try:
        manifests.validate(manifest, limit)
    except manifests.Refused as refusal:
        refuse(str(refusal))

    print(f'{track_id}: {bpm:.3f} BPM (brief {brief_bpm}), drift {drift:.3f}, first downbeat {downbeat:.3f} s, '
          f'{integrated} LUFS / {peak} dBTP, {duration:.2f} s')
    print('proposed sections — LISTEN before confirming:' if not manifest['sections_confirmed'] else 'sections:')
    for s in sections:
        lo = downbeat + s['start_bar'] * bar_s
        print(f'  {s["name"]:<12} bars {s["start_bar"]:>3}–{s["start_bar"] + s["bars"]:<3} '
              f'{lo:7.2f}–{lo + s["bars"] * bar_s:7.2f} s  energy {s["energy"]}  {s["role"]}'
              f'{"  repeatable" if s["repeatable"] else ""}')
    print(f'  final hit: bar {hit} at {hit_s:.2f} s, tail {manifest["tail_s"]:.2f} s')
    with open(args.out, 'w') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f'wrote {args.out}')


if __name__ == '__main__':
    main()
