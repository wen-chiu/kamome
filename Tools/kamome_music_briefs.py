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


# **The film library** (Chiu 2026-11-05): ten long-form briefs, the prompt style he
# preferred by ear over STYLES above. Prompts verbatim from his set, except S1 and S2,
# which this file wrote in the same style for the regions that had none. BPM and key
# are ours, so the beat grid is known before a track is generated.
#
# `style` and `mood` are what a track's manifest carries for the app's picker
# (SoundtrackPicker): style from the country table, mood from the photographs. His
# mapping, 2026-11-05: the regional briefs serve their region whatever the mood;
# everyone else gets the six general briefs, two per mood.
LIBRARY_SECONDS = 320  # longer than any film (standard_duration_max_s 300): a film only ever cuts
LIBRARY = {
    'indiepop': dict(label='01 Cinematic Indie Pop', style='anthem', mood='depart', bpm=112, key='D Major',
              prompt=(
                   "Cinematic indie pop instrumental for a beautiful travel film. Uplifting, adventurous, "
                   "warm and emotionally engaging. Driving organic drums, melodic electric guitar, warm "
                   "piano, rich melodic bass and subtle atmospheric textures. A memorable melodic hook, "
                   "sophisticated accessible chord progressions, natural phrasing and evolving "
                   "arrangement. Starts intimate, gradually builds into an uplifting emotional climax, "
                   "then resolves gracefully. Professional, cohesive, polished cinematic production. "
                   "Instrumental only, no vocals, no lyrics, no spoken words.")),
    'feelgood': dict(label='04 Feel Good Indie Pop', style='anthem', mood='depart', bpm=118, key='A Major',
              prompt=(
                   "Feel-good indie pop instrumental, bright, joyful, carefree and full of life. Catchy "
                   "melodic electric guitar, bouncy bass, crisp live drums, warm piano and subtle synth "
                   "textures. Energetic rhythmic groove, memorable melodic hook, uplifting chord "
                   "progression and lively organic arrangement. Sunny, optimistic and effortlessly "
                   "charming, with a polished modern indie production. Instrumental only, no vocals, no "
                   "lyrics, no spoken words.")),
    'downtempo': dict(label='12 Chill Downtempo', style='anthem', mood='cruise', bpm=90, key='F Major',
              prompt=(
                   "Sophisticated chill downtempo instrumental, relaxed, elegant, warm and effortlessly "
                   "cool. Laid-back electronic drums, mellow electric piano, deep rounded bass, subtle "
                   "jazz guitar and atmospheric textures. Smooth groove, tasteful jazzy harmonies, "
                   "understated melodic motifs and refined contemporary production. Relaxed but musically "
                   "engaging, with subtle variations and a natural ending. Instrumental only, no vocals, "
                   "no lyrics, no spoken words.")),
    'organicelectronic': dict(label='11 Organic Electronic', style='anthem', mood='cruise', bpm=110, key='A Minor',
              prompt=(
                   "Organic electronic cinematic instrumental, atmospheric, modern, immersive and "
                   "uplifting. Warm analog synthesizers, pulsing melodic bass, crisp electronic "
                   "percussion, delicate piano motifs and organic guitar textures. Evolving rhythmic "
                   "patterns, sophisticated electronic production, memorable melodic hook and gradual "
                   "emotional build. Contemporary, expansive and emotionally engaging, ending with a "
                   "graceful resolution. Instrumental only, no vocals, no lyrics, no spoken words.")),
    'orchestral': dict(label='02 Epic Cinematic', style='anthem', mood='epic', bpm=90, key='D Major',
              prompt=(
                   "Epic cinematic instrumental soundtrack for breathtaking travel landscapes. Majestic, "
                   "awe-inspiring, emotional and expansive. Sweeping orchestral strings, expressive piano, "
                   "deep cinematic percussion, warm brass and evolving harmonies. A beautiful memorable "
                   "melodic theme with dynamic orchestration. Begins quietly and intimately, gradually "
                   "builds into a powerful emotional climax before a graceful resolution. Sophisticated "
                   "film score production, not an aggressive action trailer. Instrumental only, no vocals, "
                   "no lyrics, no spoken words.")),
    'poprock': dict(label='06 Adventure Pop Rock', style='anthem', mood='epic', bpm=128, key='E Major',
              prompt=(
                   "Energetic cinematic pop rock instrumental, adventurous, bold and exciting. Punchy live "
                   "drums, driving electric bass, rhythmic electric guitars and uplifting piano accents. "
                   "Strong rhythmic momentum, catchy instrumental hook, dynamic transitions and a powerful "
                   "melodic chorus. A feeling of movement, freedom and discovery. Modern alternative rock "
                   "production, energetic but tasteful, with a satisfying musical ending. Instrumental "
                   "only, no vocals, no lyrics, no spoken words.")),
    'citypopcinema': dict(label='S1 Cinematic City Pop', style='citypop', mood='depart', bpm=106, key='Bb Major',
              prompt=(
                   "Cinematic city pop instrumental for a coastal road trip film. Bright, nostalgic, "
                   "stylish and warm. Clean funky electric guitar, smooth electric piano, melodic slap "
                   "bass, tight live drums and lush analog synth pads. A memorable melodic hook, rich "
                   "jazzy chord progressions, natural phrasing and an evolving arrangement. Starts with a "
                   "light groove, opens into a sunny, uplifting chorus, then resolves gently like the end "
                   "of a summer evening drive. Warm, polished, handcrafted production, not cheesy or "
                   "retro-parody. Instrumental only, no vocals, no lyrics, no spoken words.")),
    'nordiccinema': dict(label='S2 Nordic Cinematic Post-Rock', style='nordic', mood='epic', bpm=92, key='B Minor',
              prompt=(
                   "Cinematic Nordic post-rock instrumental for vast wild landscapes. Spacious, "
                   "awe-inspiring, cold, clear and hopeful. Shimmering delayed electric guitars, felt "
                   "piano, deep warm bass, slowly building live drums and swelling strings. A simple "
                   "beautiful melodic theme that grows over evolving textures. Begins quietly like an "
                   "early morning on an empty road, gradually builds into a soaring emotional climax, then "
                   "settles into calm. Organic, atmospheric and polished production, not harsh or "
                   "aggressive. Instrumental only, no vocals, no lyrics, no spoken words.")),
    'tropicalacoustic': dict(label='07 Tropical Acoustic', style='tropical', mood='cruise', bpm=98, key='G Major',
              prompt=(
                   "Tropical acoustic instrumental, warm, breezy, relaxed and joyful. Fingerpicked "
                   "acoustic guitar, light tropical percussion, melodic bass, soft piano and subtle "
                   "marimba. Flowing rhythmic groove, charming melodic phrases and a sunlit island "
                   "atmosphere. Organic, sophisticated and cinematic, with a memorable melody and natural "
                   "instrumental interplay. Avoid childish ukulele sounds and generic commercial stock "
                   "music. Instrumental only, no vocals, no lyrics, no spoken words.")),
    'eurofolk': dict(label='08 European Folk', style='folk', mood='cruise', bpm=104, key='G Major',
              prompt=(
                   "Cinematic European folk instrumental, charming, warm, pastoral and nostalgic. Acoustic "
                   "guitar, mandolin, gentle accordion, upright bass and organic brushed percussion. "
                   "Beautiful folk-inspired melody, elegant chord progression and relaxed rhythmic "
                   "movement. Picturesque countryside atmosphere, intimate storytelling and natural "
                   "acoustic textures. Refined, warm and cinematic production. Instrumental only, no "
                   "vocals, no lyrics, no spoken words.")),
}


def library(only=None):
    """Yield (brief id, spec) for the film library, in file order."""
    for brief_id, spec in LIBRARY.items():
        if not only or brief_id in only:
            yield brief_id, spec


def library_prompt(spec):
    """The text a model receives: the prompt with its tempo and key appended."""
    return f"{spec['prompt']} {spec['bpm']} BPM, {spec['key']}."


def library_seed(brief_id, take):
    """Fixed per brief and take. 'extra' is the key the first takes were made with
    (2026-11-03), kept so those takes regenerate exactly."""
    return seed_for(brief_id, 'extra', take)


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
