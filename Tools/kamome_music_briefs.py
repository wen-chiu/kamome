"""The road-trip music briefs, shared by every desk generator.

Used by Tools/kamome-acestep.py and Tools/kamome-stableaudio.py, so both models
get exactly the same prompts and can be compared take for take
(Docs/handoff-music-rethink.md, Part D). Stdlib only. No trip data.
"""
import html
import json
import os
import zlib

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
# beat grid is known before the film is cut to it. No artist or song names, ever.
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
    """Yield (style, mood, bpm, key, caption) with the common tail appended."""
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


ENGINES = (('acestep', 'ACE-Step 1.5'), ('stableaudio', 'Stable Audio 3'))


def write_compare_page(root):
    """One page per music root: each brief, every engine's takes side by side.

    Reads <root>/<engine>/manifest.json for each engine present; file links are
    relative, so the page works opened straight from Finder.
    """
    manifests = {}
    for engine, _ in ENGINES:
        path = os.path.join(root, engine, 'manifest.json')
        if os.path.exists(path):
            with open(path) as f:
                manifests[engine] = json.load(f)
    rows = []
    for style, spec in STYLES.items():
        rows.append(f'<h2>{html.escape(style)} <small>{html.escape(spec["regions"])}</small></h2>')
        for mood, label in MOODS.items():
            bpm, key, _ = spec[mood]
            cells = []
            for engine, name in ENGINES:
                takes = [m for m in manifests.get(engine, [])
                         if m['style'] == style and m['mood'] == mood]
                players = ''.join(
                    f'<div class="p">seed {m["seed"]}<audio controls preload="none" '
                    f'src="{html.escape(engine + "/" + m["file"])}"></audio></div>' for m in takes)
                cells.append(f'<td><b>{name}</b>{players or "<div class=p>—</div>"}</td>')
            rows.append(f'<h3>{html.escape(label)} <small>{bpm} BPM · {html.escape(key)}</small></h3>'
                        f'<table><tr>{"".join(cells)}</tr></table>')
    page = ('<!doctype html><meta charset="utf-8"><meta name="viewport" '
            'content="width=device-width,initial-scale=1"><title>Kamome music takes</title>'
            '<style>body{font:15px -apple-system,sans-serif;max-width:980px;margin:24px auto;'
            'padding:0 16px}small{color:#777;font-weight:normal}table{width:100%;'
            'table-layout:fixed;border-collapse:collapse}td{vertical-align:top;padding:6px;'
            'border-top:1px solid #ddd}.p{margin:6px 0;font-size:12px;color:#555}'
            'audio{width:100%}@media(max-width:640px){td{display:block}}</style>'
            '<h1>Kamome road-trip music</h1><p>Same brief, same seeds, two models. '
            'Score each take 1–10 against 「壯闊有趣的公路旅行」.</p>' + '\n'.join(rows))
    with open(os.path.join(root, 'compare.html'), 'w') as f:
        f.write(page)
