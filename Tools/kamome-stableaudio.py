#!/usr/bin/env python3
"""Desk only: generate road-trip film music with Stable Audio 3 on an Apple Silicon Mac.

The same 15 briefs and seeds as Tools/kamome-acestep.py (Tools/kamome_music_briefs.py),
so the two models can be compared take for take. It runs the MLX route that
`Tools/kamome-stableaudio.sh setup` installs, entirely on this Mac; nothing but
the prompts is used. No trip data.

    python3 Tools/kamome-stableaudio.py list
    python3 Tools/kamome-stableaudio.py generate                    # medium, 2 takes, 120 s
    python3 Tools/kamome-stableaudio.py generate --only tropical --mood depart --takes 1
    python3 Tools/kamome-stableaudio.py generate --dit sm-music     # the fast small model
    python3 Tools/kamome-stableaudio.py generate --dry-run

It refuses to run until the Community License registration is recorded
(`kamome-stableaudio.sh setup`): commercial use requires it.

Output (never committed): ~/Kamome-music/stableaudio/<style>/<style>-<mood>-s<seed>.wav,
manifest.json (prompt, seed, model, commit, licence record), and
~/Kamome-music/compare.html beside ACE-Step's takes.
"""
import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kamome_music_briefs import MOODS, STYLES, briefs, seed_for, write_compare_page  # noqa: E402

SA3_COMMIT = '5f5e6ac21ae9ff78a6e8847eb7a1dcbe969ffb84'  # same pin as kamome-stableaudio.sh
ROOT = os.path.expanduser(os.environ.get('KAMOME_MUSIC_DIR', '~/Kamome-music'))
MLX_DIR = os.path.join(ROOT, 'stable-audio-3', 'optimized', 'mlx')
RECORD = os.path.join(ROOT, 'stable-audio-3', 'kamome-licence.json')
# Each DiT with the decoder it was trained with, and its longest output.
DITS = {'medium': ('same-l', 380.0), 'sm-music': ('same-s', 120.0)}


def fail(msg):
    print(f'kamome-stableaudio: {msg}', file=sys.stderr)
    sys.exit(1)


def prompt_for(bpm, key, caption):
    # Stable Audio 3 has no tempo or key parameter; both go into the text, and the
    # beat grid is measured afterwards whichever model made the track.
    return f'{caption}, {bpm} BPM, {key}'


def command(dit, prompt, seconds, seed, steps, cfg, out):
    decoder, _ = DITS[dit]
    return [os.path.join(MLX_DIR, '.venv', 'bin', 'python'), 'scripts/sa3_mlx.py',
            '--prompt', prompt, '--dit', dit, '--decoder', decoder,
            '--seconds', f'{seconds:g}', '--seed', str(seed), '--steps', str(steps),
            '--cfg', f'{cfg:g}', '--out', out]


def licence_record():
    if not os.path.exists(RECORD):
        fail('no Community License registration recorded. Commercial use needs it: '
             'run Tools/kamome-stableaudio.sh setup')
    with open(RECORD) as f:
        rec = json.load(f)
    if not rec.get('registrant') or not rec.get('weights_licence_files'):
        fail(f'{RECORD} is incomplete; run Tools/kamome-stableaudio.sh setup again')
    return rec


def generate(args):
    todo = [(b, take) for b in briefs(args.only, args.mood) for take in range(args.takes)]
    if not todo:
        fail('nothing matches --only/--mood')
    out = os.path.expanduser(args.out)
    if args.dry_run:
        for (style, mood, bpm, key, caption), take in todo:
            seed = seed_for(style, mood, take)
            dest = os.path.join(out, style, f'{style}-{mood}-s{seed}.wav')
            print(' '.join(json.dumps(a, ensure_ascii=False) if ' ' in a else a for a in
                           command(args.dit, prompt_for(bpm, key, caption), args.duration,
                                   seed, args.steps, args.cfg, dest)))
        return
    rec = licence_record()
    if not os.path.exists(os.path.join(MLX_DIR, '.venv', 'bin', 'python')):
        fail('Stable Audio 3 is not installed; run Tools/kamome-stableaudio.sh setup')

    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, 'manifest.json')
    manifest = json.load(open(mpath)) if os.path.exists(mpath) else []
    done = {m['file'] for m in manifest}
    failures = 0
    for n, ((style, mood, bpm, key, caption), take) in enumerate(todo, 1):
        seed = seed_for(style, mood, take)
        rel = f'{style}/{style}-{mood}-s{seed}.wav'
        dest = os.path.join(out, rel)
        if rel in done and os.path.exists(dest):
            print(f'[{n}/{len(todo)}] {rel} — already there')
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        prompt = prompt_for(bpm, key, caption)
        print(f'[{n}/{len(todo)}] {style}/{mood} take {take + 1} (seed {seed}, {args.dit}) …', flush=True)
        t0 = time.time()
        proc = subprocess.run(command(args.dit, prompt, args.duration, seed, args.steps, args.cfg, dest),
                              cwd=MLX_DIR, capture_output=True, text=True)
        if proc.returncode != 0 or not os.path.exists(dest):
            failures += 1
            tail = (proc.stderr or proc.stdout).strip().splitlines()[-3:]
            print('    failed: ' + ' | '.join(tail), file=sys.stderr)
            continue
        manifest = [m for m in manifest if m['file'] != rel]
        manifest.append({
            'file': rel, 'style': style, 'mood': mood, 'bpm': bpm, 'key': key,
            'time_signature': '4/4', 'duration_s': args.duration, 'seed': seed,
            'prompt': prompt, 'steps': args.steps, 'cfg': args.cfg,
            'engine': 'stable-audio-3-mlx', 'dit_model': args.dit, 'decoder': DITS[args.dit][0],
            'stable_audio_3_commit': SA3_COMMIT,
            'licence': rec.get('licence'), 'licence_registrant': rec.get('registrant'),
            'licence_recorded_on': rec.get('recorded_on'),
            'weights_licence_sha256': [f.get('sha256') for f in rec['weights_licence_files']],
            'seconds_to_generate': round(time.time() - t0, 1),
        })
        with open(mpath, 'w') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
        write_compare_page(os.path.dirname(out))
        print(f'    → {rel} ({time.time() - t0:.0f}s)')
    print(f'\n{len(manifest)} takes in {out}; open {os.path.dirname(out)}/compare.html')
    if failures:
        fail(f'{failures} take(s) failed; re-run the same command to retry only those')


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('list', help='print the briefs as Stable Audio 3 receives them')
    g = sub.add_parser('generate', help='generate the briefs on this Mac')
    g.add_argument('--only', nargs='+', choices=list(STYLES), help='styles to generate')
    g.add_argument('--mood', nargs='+', choices=list(MOODS), help='moods to generate')
    g.add_argument('--takes', type=int, default=2, help='seeds per brief (default 2)')
    g.add_argument('--duration', type=float, default=120.0, help='seconds (default 120)')
    g.add_argument('--dit', choices=list(DITS), default='medium',
                   help='medium (1.4 B, better) or sm-music (fast); default medium')
    g.add_argument('--steps', type=int, default=8, help='sampling steps (distilled for 8)')
    g.add_argument('--cfg', type=float, default=1.0, help='guidance; 1.0 = off (model default)')
    g.add_argument('--out', default=os.path.join(ROOT, 'stableaudio'))
    g.add_argument('--dry-run', action='store_true')
    args = p.parse_args()
    if args.cmd == 'list':
        for style, mood, bpm, key, caption in briefs():
            print(f'{style:9} {mood:7} {prompt_for(bpm, key, caption)}')
        return
    longest = DITS[args.dit][1]
    if args.takes < 1 or not 10 <= args.duration <= longest:
        fail(f'--takes must be ≥ 1 and --duration 10–{longest:g} s for {args.dit}')
    generate(args)


if __name__ == '__main__':
    main()
