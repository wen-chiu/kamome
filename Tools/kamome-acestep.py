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
plus manifest.json (prompt, tempo, key, seed, models, ACE-Step commit) and
listen.html to compare takes in a browser.
"""
import argparse
import html
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib

ACE_COMMIT = 'ca1e85fe9430179831e6bc6be790c332190a3866'  # same pin as kamome-acestep.sh
INSTRUMENTAL = '[Instrumental]'
TAIL = 'instrumental, no vocals, polished modern mix, wide stereo, professional mastering'

# Moods follow a road-trip film's arc: setting off, the drive, the big view.
MOODS = {
    'depart': '出發 — bright, hopeful, light on its feet',
    'cruise': '巡航 — steady groove for the open road, relaxed but moving',
    'epic': '壯闊 — the big landscape: builds to a soaring, euphoric climax',
}

# Chiu's table (2026-10-29), plus `anthem` for every other country (his call).
# Each brief: (bpm, key, caption). Keys and tempos are set, never auto, so the
# beat grid is known before the film is cut to it.
STYLES = {
    'citypop': {
        'regions': 'JP TW KR — 輕 lo-fi、city pop 風、木吉他',
        'depart': (104, 'F Major', 'japanese city pop, bright clean electric guitar cutting, '
                   'acoustic guitar strums, slap bass, rhodes electric piano, tight live drums, '
                   'warm analog synth brass stabs, sunny seaside drive, nostalgic and cheerful'),
        'cruise': (88, 'D Major', 'lo-fi city pop, mellow jazzy chords, rhodes, nylon-string guitar, '
                   'soft boom-bap drums with swing, warm bass, vinyl warmth, late afternoon city drive, '
                   'relaxed and fond'),
        'epic': (112, 'A Major', 'city pop anthem, full band, funky bass, bright guitars, horn section, '
                 'lush strings, driving drums, key change into a big final chorus, '
                 'coastal highway at sunset, joyful and grand'),
    },
    'nordic': {
        'regions': 'IS NO — ambient、鋼琴、post-rock',
        'depart': (96, 'D Major', 'cinematic post-rock intro, felt piano motif, shimmering delayed '
                   'electric guitars, soft cymbal swells, cold clear morning, quiet anticipation '
                   'opening into hope'),
        'cruise': (84, 'E Major', 'ambient post-rock, warm pad drones, gentle piano, reverb-washed '
                   'guitars, slow steady kick and toms, glacial road through wide valleys, '
                   'calm and awe-struck'),
        'epic': (100, 'B Minor', 'epic post-rock crescendo, tremolo electric guitars, '
                 'thunderous live drums, soaring string orchestra, deep bass, '
                 'massive waterfall and fjord, overwhelming and triumphant'),
    },
    'tropical': {
        'regions': 'VN TH — 溫暖的 acoustic、輕 tropical',
        'depart': (100, 'D Major', 'warm acoustic tropical pop, steel-string and nylon guitars, '
                   'marimba accents, congas and shaker, bass guitar, bright piano, '
                   'sunny morning departure, playful and uplifting'),
        'cruise': (92, 'G Major', 'laid-back tropical house groove, plucked acoustic guitar, '
                   'soft four-on-the-floor, warm sub bass, airy pads, light percussion, '
                   'palm-lined coastal road, easy and carefree'),
        'epic': (108, 'E Major', 'euphoric tropical pop, big acoustic strums, steel drums, '
                 'live drums and claps, layered synths, rising strings, '
                 'island viewpoint over the sea, celebratory and grand'),
    },
    'folk': {
        'regions': 'NZ AU — indie folk',
        'depart': (110, 'G Major', 'upbeat indie folk, fingerpicked and strummed acoustic guitars, '
                   'banjo, foot stomps and hand claps, upright bass, glockenspiel sparkle, '
                   'setting off on a sunny road, joyful and free'),
        'cruise': (96, 'C Major', 'warm indie folk groove, acoustic guitar, brushed drums, '
                   'mandolin, hammond organ, bass guitar, long open highway through green hills, '
                   'content and easygoing'),
        'epic': (118, 'D Major', 'anthemic indie folk rock, big strummed guitars, stomping kick and '
                 'tambourine, gang-vocal style lead melody on violin and whistle, piano, '
                 'swelling strings, mountains and coastline, heart-on-sleeve euphoria'),
    },
    'anthem': {
        'regions': 'everyone else — feel-good pop (default: Chiu decides)',
        'depart': (120, 'E Major', 'feel-good indie pop, bright strummed acoustic guitar, '
                   'punchy live drums, claps, bouncy bass guitar, synth pad, glockenspiel hook, '
                   'road trip morning, excited and fun'),
        'cruise': (110, 'C Major', 'summer indie pop groove, clean electric guitar riffs, '
                   'tight drums, warm bass, light synths, windows down on the highway, '
                   'carefree and sunny'),
        'epic': (124, 'A Major', 'stadium pop road trip anthem, driving drums, big guitars, '
                 'soaring synth lead, strings, bass, huge chorus energy, '
                 'cinematic drone shot of the open road, euphoric and grand'),
    },
}


def briefs(only=None, moods=None):
    for style, spec in STYLES.items():
        if only and style not in only:
            continue
        for mood in MOODS:
            if moods and mood not in moods:
                continue
            bpm, key, caption = spec[mood]
            yield style, mood, bpm, key, f'{caption}, {TAIL}'


def seed_for(style, mood, take):
    """Fixed per brief and take, so a kept track can be regenerated exactly."""
    return zlib.crc32(f'kamome/{style}/{mood}/{take}'.encode()) % 2_000_000_000


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


def write_listen_page(out, manifest):
    rows = []
    for style, spec in STYLES.items():
        items = [m for m in manifest if m['style'] == style]
        if not items:
            continue
        rows.append(f'<h2>{html.escape(style)} <small>{html.escape(spec["regions"])}</small></h2>')
        for m in items:
            rows.append(
                f'<div class="t"><b>{html.escape(m["mood"])}</b> · {m["bpm"]} BPM · '
                f'{html.escape(m["key"])} · seed {m["seed"]}<br>'
                f'<audio controls preload="none" src="{html.escape(m["file"])}"></audio></div>')
    page = ('<!doctype html><meta charset="utf-8"><meta name="viewport" '
            'content="width=device-width,initial-scale=1"><title>Kamome music takes</title>'
            '<style>body{font:15px -apple-system,sans-serif;max-width:760px;margin:24px auto;'
            'padding:0 16px}small{color:#777;font-weight:normal}.t{margin:10px 0}'
            'audio{width:100%}</style><h1>Kamome × ACE-Step 1.5</h1>'
            '<p>Score each take 1–10 against 「壯闊有趣的公路旅行」.</p>' + '\n'.join(rows))
    with open(os.path.join(out, 'listen.html'), 'w') as f:
        f.write(page)


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
        write_listen_page(out, manifest)
        print(f'    → {rel} ({time.time() - t0:.0f}s)')
    print(f'\n{len(manifest)} takes in {out}; open listen.html to compare.')
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
