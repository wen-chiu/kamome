#!/usr/bin/env python3
"""Desk only: generate road-trip film music with a local ACE-Step 1.5 server.

The experiment in Docs/handoff-music-rethink.md, Part D: five regional styles x
three moods, instrumental, each at a set tempo and key so a film's turns can be
snapped to its beat later. Pure stdlib; it talks to the API that
`Tools/kamome-acestep.sh serve` starts on 127.0.0.1 and sends it nothing but
the prompts below. No trip data is involved.

    python3 Tools/kamome-acestep.py list
    python3 Tools/kamome-acestep.py generate                       # all 15 briefs, 2 takes each
    python3 Tools/kamome-acestep.py generate --only tropical --takes 3
    python3 Tools/kamome-acestep.py generate --dry-run             # print the requests

Output (never committed): ~/Kamome-music/acestep/<style>/<style>-<mood>-s<seed>.<fmt>,
plus manifest.json (prompt, tempo, key, seed, models, ACE-Step commit), and
~/Kamome-music/compare.html beside Stable Audio 3's takes of the same briefs.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ACE_COMMIT = 'ca1e85fe9430179831e6bc6be790c332190a3866'  # same pin as kamome-acestep.sh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kamome_music_briefs import (INSTRUMENTAL, MOODS, STYLES, briefs, seed_for,  # noqa: E402
                                 write_compare_page)


def request(style, mood, bpm, key, caption, seed, args):
    return {
        'prompt': caption,
        'lyrics': INSTRUMENTAL,
        'bpm': bpm,
        'key_scale': key,
        'time_signature': '4',
        'audio_duration': args.duration,
        'thinking': not args.no_lm,
        'use_cot_caption': False,      # keep our caption as written
        'use_cot_language': False,
        'inference_steps': args.steps,
        'use_random_seed': False,
        'seed': seed,
        'batch_size': 1,
        'audio_format': args.format,
    }


def call(base, path, payload=None, timeout=60):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=data,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def fail(msg):
    print(f'kamome-acestep: {msg}', file=sys.stderr)
    sys.exit(1)


def wait_for(base, task_id, poll_s, limit_s):
    start = time.time()
    while time.time() - start < limit_s:
        body = call(base, '/query_result', {'task_id_list': [task_id]})
        item = (body.get('data') or [{}])[0]
        if item.get('status') == 1:
            result = item.get('result')
            return json.loads(result) if isinstance(result, str) else result
        if item.get('status') == 2:
            raise RuntimeError(f'task failed: {item.get("result") or body.get("error")}')
        time.sleep(poll_s)
    raise RuntimeError(f'no result after {limit_s:.0f}s')


def download(base, file_url, dest):
    url = file_url if file_url.startswith('http') else base + file_url
    tmp = dest + '.part'
    with urllib.request.urlopen(url, timeout=300) as r, open(tmp, 'wb') as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, dest)


def generate(args):
    todo = [(b, take) for b in briefs(args.only, args.mood) for take in range(args.takes)]
    if not todo:
        fail('nothing matches --only/--mood')
    if args.dry_run:
        for (style, mood, bpm, key, caption), take in todo:
            print(json.dumps(request(style, mood, bpm, key, caption,
                                     seed_for(style, mood, take), args), ensure_ascii=False))
        return
    base = args.server.rstrip('/')
    try:
        call(base, '/health', timeout=5)
    except (urllib.error.URLError, OSError) as e:
        fail(f'no ACE-Step server at {base} ({e}); start it with Tools/kamome-acestep.sh serve')

    out = os.path.expanduser(args.out)
    os.makedirs(out, exist_ok=True)
    mpath = os.path.join(out, 'manifest.json')
    manifest = json.load(open(mpath)) if os.path.exists(mpath) else []
    done = {m['file'] for m in manifest}
    failures = 0
    for n, ((style, mood, bpm, key, caption), take) in enumerate(todo, 1):
        seed = seed_for(style, mood, take)
        rel = f'{style}/{style}-{mood}-s{seed}.{args.format}'
        dest = os.path.join(out, rel)
        if rel in done and os.path.exists(dest):
            print(f'[{n}/{len(todo)}] {rel} — already there')
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        print(f'[{n}/{len(todo)}] {style}/{mood} take {take + 1} (seed {seed}) …', flush=True)
        t0 = time.time()
        try:
            body = call(base, '/release_task', request(style, mood, bpm, key, caption, seed, args))
            task_id = (body.get('data') or {}).get('task_id')
            if not task_id:
                raise RuntimeError(f'no task id: {body.get("error") or body}')
            results = wait_for(base, task_id, args.poll, args.timeout)
            first = results[0] if isinstance(results, list) else results
            download(base, first['file'], dest)
        except (RuntimeError, urllib.error.URLError, OSError, KeyError, IndexError) as e:
            failures += 1
            print(f'    failed: {e}', file=sys.stderr)
            continue
        manifest = [m for m in manifest if m['file'] != rel]
        manifest.append({
            'file': rel, 'style': style, 'mood': mood, 'bpm': bpm, 'key': key,
            'time_signature': '4/4', 'duration_s': args.duration, 'seed': seed,
            'prompt': caption, 'lyrics': INSTRUMENTAL, 'steps': args.steps,
            'lm': not args.no_lm, 'dit_model': first.get('dit_model'),
            'lm_model': first.get('lm_model'), 'server_metas': first.get('metas'),
            'ace_step_commit': ACE_COMMIT, 'seconds_to_generate': round(time.time() - t0, 1),
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
    sub.add_parser('list', help='print the briefs')
    g = sub.add_parser('generate', help='generate the briefs on a running server')
    g.add_argument('--only', nargs='+', choices=list(STYLES), help='styles to generate')
    g.add_argument('--mood', nargs='+', choices=list(MOODS), help='moods to generate')
    g.add_argument('--takes', type=int, default=2, help='seeds per brief (default 2)')
    g.add_argument('--duration', type=float, default=120.0, help='seconds (default 120)')
    g.add_argument('--steps', type=int, default=8, help='diffusion steps (turbo: 8)')
    g.add_argument('--no-lm', action='store_true', help='skip the 5 Hz planner (faster, flatter)')
    g.add_argument('--format', default='wav', choices=['wav', 'flac', 'mp3'])
    g.add_argument('--server', default='http://127.0.0.1:8001')
    g.add_argument('--out', default=os.path.join(os.environ.get('KAMOME_MUSIC_DIR', '~/Kamome-music'), 'acestep'))
    g.add_argument('--poll', type=float, default=3.0)
    g.add_argument('--timeout', type=float, default=1800.0, help='per take, seconds')
    g.add_argument('--dry-run', action='store_true')
    args = p.parse_args()
    if args.cmd == 'list':
        for style, mood, bpm, key, caption in briefs():
            print(f'{style:9} {mood:7} {bpm:4} BPM  {key:8}  {caption}')
        return
    if args.takes < 1 or not 10 <= args.duration <= 600:
        fail('--takes must be ≥ 1 and --duration 10–600 s')
    generate(args)


if __name__ == '__main__':
    main()
