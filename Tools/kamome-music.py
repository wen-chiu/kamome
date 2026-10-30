#!/usr/bin/env python3
"""Kamome's own film music: five loop sets for road-trip films, composed here.

Why this exists (Chiu, 2026-10-29). The film is to have music, and only music
that is free to use. Free music that may be *bundled inside an app* and is not
registered with Content ID is a short list, so the music is written here.

**Round 3 is written by subtraction (Chiu, 2026-10-30).** Two richer rounds
sounded subtly wrong: jazz chords (maj9, #11, add9 clusters) stacked on several
harmony instruments rubbed against each other, and synthesised imitations of
acoustic instruments (flute, whistle, guitar) sat in the uncanny valley. Chiu's
reference — the music of a Polarsteps trip film, measured here — is the
opposite: 118 BPM, plain major and minor triads from one key, a short hook
repeated, four layers. So every style now keeps these rules, and the first one
is checked by `check_melody`, which refuses to render a breach:

1. **Harmony is triads from the key, one chord a bar**, in progressions found in
   any free pop chord chart (I–V–vi–IV, I–IV–vi–V, IV–V–iii–vi, vi–IV–I–V). A
   melody note on beat 1 or 3, or held a beat or longer, is a chord tone; any
   other note is in the scale.
2. **At most four layers**: drums, bass, one chord instrument, one melody.
3. **Recorded instruments, or sounds that are honestly electronic** (a kick, a
   bass, a pluck) — no synthesised imitation of an acoustic instrument.
4. **No swing, no crackle, no pads.**

**Where every sound comes from — the licence is the reason for each line:**

- **Acoustic instruments are CC0 1.0 recordings** from the Versilian Community
  Sample Library (VCSL, Versilian Studios): pianos, vibraphone, marimba,
  glockenspiel, wind chimes and every drum and percussion sound. CC0 is a
  public-domain dedication — commercial use, no credit owed. Pinned to one
  commit (`VCSL_COMMIT`) so a render is repeatable. Chiu chose recorded over
  synthesised on 2026-10-29.
- **The electronic sounds are synthesised in this file** from sine and saw
  waves: the kick, the bass and the pop style's pluck.

Nothing else goes in: no other sample, sound font or recording.

    python3 Tools/kamome-music.py fetch                     # the VCSL subset, once
    python3 Tools/kamome-music.py render                    # all five styles
    python3 Tools/kamome-music.py render --style cinematic
    python3 Tools/kamome-music.py arrange --style cinematic --example
    python3 Tools/kamome-music.py arrange --style cinematic --timeline film.json
    python3 Tools/kamome-music.py style --country IS

`render` writes, per style, to `~/Kamome-music/<style>/` (or `--out`):

    intro.wav     loop      before the car moves (the title card): chords only
    travel_a.wav  loop      driving: drums, bass, chords, the hook
    travel_b.wav  loop      driving, fuller: the hook and its answer
    stop.wav      loop      a stop's photos: chords and the hook, softly
    riser.wav     one-shot  a cymbal swelling into a turn; its anchor is the beat
    hit_big.wav   one-shot  the beat the car moves off or a crossing starts
    hit_soft.wav  one-shot  the beat a stop's photos open
    outro.wav     one-shot  the end card
    beatmap.json  tempo, loop lengths, one-shot anchors

**The beat map is exact, not detected**: the music is composed on its grid, and
each tempo is chosen so a beat is a whole number of samples at 44.1 kHz.

**Why a loop can change on any beat.** Within a style every loop plays the same
4-bar progression and is a whole number of progressions long, and every loop's
phase is the film's clock: bar k of every loop sits on the same chord.

`arrange` takes a film's events — `{"duration_s": 64, "events": [{"t": 6.5,
"kind": "go"}, ...]}`, kinds `go` (the car moves), `stop` (a stop's photos
open), `crossing` (a crossing's card), `end` (the end card) — and writes one
soundtrack. Each event snaps to the nearest beat and the shift is printed: the
film is not moved here, which is the export's job once this is wired in.

Pure stdlib, like `center-sprites.py`; `fetch` needs `git`. Styles render in
parallel, one per core.
"""

import argparse
import json
import math
import os
import random
import re
import subprocess
import sys
import wave
from array import array
from multiprocessing import Pool

SR = 44100
TAU = 2.0 * math.pi
NYQ_SAFE = SR * 0.45


def zeros(n):
    return array('d', bytes(8 * n))


def _fail(msg):
    print(f'kamome-music: {msg}', file=sys.stderr)
    sys.exit(2)


# ---------------------------------------------------------------- pitch and harmony

_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
MAJOR = (0, 2, 4, 5, 7, 9, 11)


def midi(name):
    """'F#4' -> 66, 'Bb1' -> 34 (scientific pitch: middle C is C4)."""
    pc, i = _PC[name[0]], 1
    while name[i] in '#b':
        pc += 1 if name[i] == '#' else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + pc


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def _lp_coef(fc):
    return 1.0 - math.exp(-TAU * fc / SR)


def triad(name):
    """'C#m' -> pitch classes of root, third, fifth. Triads only, on purpose."""
    m = re.match(r'([A-G])([#b]?)(m?)$', name)
    if not m:
        _fail(f'{name!r} is not a major or minor triad')
    root = (_PC[m.group(1)] + {'#': 1, 'b': -1, '': 0}[m.group(2)]) % 12
    return (root, (root + (3 if m.group(3) else 4)) % 12, (root + 7) % 12)


def voice(prog, low):
    """Close-position triads, each the nearest move from the one before, every
    note in [low, low + 13]: the voicing a pianist's right hand would find."""
    out, prev = [], None
    for name in prog:
        pcs = triad(name)
        cands = []
        for base in range(low, low + 12):
            if base % 12 in pcs:
                v = [base]
                for _ in range(2):
                    nxt = v[-1] + 1
                    while nxt % 12 not in pcs or nxt % 12 in [x % 12 for x in v]:
                        nxt += 1
                    v.append(nxt)
                if v[-1] <= low + 13:
                    cands.append(v)
        if prev is None:
            pick = min(cands, key=lambda v: abs(v[1] - (low + 7)))
        else:
            pick = min(cands, key=lambda v: sum(abs(a - b) for a, b in zip(v, prev)))
        out.append(pick)
        prev = pick
    return out


def root_in(name, low):
    """The chord's root at or above `low`, within an octave."""
    r = triad(name)[0]
    return low + (r - low) % 12


# ---------------------------------------------------------------- synthesised (electronic) sounds
#
# Each takes (frequency in Hz, held seconds, velocity 0-1, seed) and returns a
# mono buffer that includes its own release.

def bass(f, dur, vel, seed, bright=0.35, attack=0.005):
    """Bass: a few harmonics on purpose, so a phone speaker still hears the line."""
    n_on = int(dur * SR)
    n = n_on + int(0.08 * SR)
    out = zeros(n)
    w = TAU * f / SR
    k_dec = math.exp(-1.0 / (0.4 * SR))
    k_rel = math.exp(-1.0 / (0.025 * SR))
    k_pl = math.exp(-1.0 / (0.012 * SR))
    att = max(1, int(attack * SR))
    d, g, pl = 1.0, 1.0, 1.0
    h2, h3 = bright, bright * 0.35
    norm = math.tanh(1.05)
    sin, tanh = math.sin, math.tanh
    for t in range(n):
        ph = w * t
        y = sin(ph) + h2 * sin(2 * ph) + h3 * sin(3 * ph) + 0.25 * pl * sin(5 * ph)
        y = tanh(1.05 * y) / norm
        e = 0.55 + 0.45 * d
        if t < att:
            e *= t / att
        if t >= n_on:
            g *= k_rel
            e *= g
        out[t] = y * e
        d *= k_dec
        pl *= k_pl
    return out


_SAW = {}
_TAB = 2048


def _saw(nh):
    """One band-limited, gently darkened saw cycle, cached by harmonic count."""
    if nh not in _SAW:
        tab = zeros(_TAB + 1)
        for k in range(1, nh + 1):
            a = (1.0 / k) / (1.0 + (k / 5.0) ** 2)
            for i in range(_TAB):
                tab[i] += a * math.sin(TAU * k * i / _TAB)
        peak = max(abs(v) for v in tab)
        for i in range(_TAB):
            tab[i] /= peak
        tab[_TAB] = tab[0]
        _SAW[nh] = tab
    return _SAW[nh]



def pluck_lead(f, dur, vel, seed, bright=4500.0, decay=0.35):
    """The pop style's lead: two detuned saws through a low-pass that closes
    fast — the house 'pluck'. Honestly electronic; it imitates nothing."""
    rng = random.Random(seed)
    n_on = int(dur * SR)
    n = n_on + int(0.15 * SR)
    out = zeros(n)
    tab = _saw(max(1, min(24, int(NYQ_SAFE / (f * 1.01)))))
    k_amp = math.exp(-1.0 / (decay * SR))
    k_env = math.exp(-1.0 / (0.09 * SR))
    k_rel = math.exp(-1.0 / (0.04 * SR))
    incs = [f * 2 ** (c / 1200.0) * _TAB / SR for c in (-6.0, 6.0)]
    phs = [rng.uniform(0, _TAB) for _ in incs]
    amp, env, g, y = 1.0, 1.0, 1.0, 0.0
    att = int(0.003 * SR)
    exp = math.exp
    for t in range(n):
        s = 0.0
        for j in (0, 1):
            ph = phs[j]
            i = int(ph)
            s += tab[i] + (ph - i) * (tab[i + 1] - tab[i])
            ph += incs[j]
            if ph >= _TAB:
                ph -= _TAB
            phs[j] = ph
        y += (1.0 - exp(-TAU * (250.0 + bright * vel * env) / SR)) * (s * 0.5 - y)
        e = (0.25 + 0.75 * amp) * (t / att if t < att else 1.0)
        if t >= n_on:
            g *= k_rel
            e *= g
        out[t] = y * e
        amp *= k_amp
        env *= k_env
    return out


def kick(f, dur, vel, seed, f_start=120.0, f_end=48.0, sweep=0.035, decay=0.24,
         click=0.04, drive=0.8, length=0.6):
    """An electronic kick: VCSL's bass drum is a concert drum, too long and too
    wide to sit under a pop or lo-fi groove."""
    rng = random.Random(seed)
    n = int(length * SR)
    out = zeros(n)
    ks = math.exp(-1.0 / (sweep * SR))
    kd = math.exp(-1.0 / (decay * SR))
    m = int(0.003 * SR)
    ph, s, e = 0.0, 1.0, 1.0
    norm = math.tanh(drive)
    sin, tanh = math.sin, math.tanh
    for t in range(n):
        ph += TAU * (f_end + (f_start - f_end) * s) / SR
        y = sin(ph) * e
        if t < m:
            y += click * rng.uniform(-1, 1) * (1 - t / m)
        out[t] = tanh(drive * y) / norm
        s *= ks
        e *= kd
    return out


# ---------------------------------------------------------------- recorded instruments (VCSL, CC0)

VCSL_URL = 'https://github.com/sgossner/VCSL'
VCSL_COMMIT = 'c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e'
_S = 'Idiophones/Struck Idiophones/'
_M = 'Membranophones/Struck Membranophones/'
_Z = 'Chordophones/Zithers/'
# What `fetch` checks out: only the recordings the styles play.
VCSL_PATHS = (
    'LICENSE',
    _Z + 'Upright Piano, Yamaha/Sustains/*_vl2_rr1.wav',
    _Z + 'Upright Piano, Yamaha/Sustains/*_vl3_rr1.wav',
    _Z + 'Grand Piano, Kawai/Sustains/*_v2_rr1_*',
    _Z + 'Grand Piano, Kawai/Sustains/*_v3_rr1_*',
    _S + 'Vibraphone/Soft Mallets/*',
    _S + 'Marimba/*',
    _S + 'Glockenspiel/*',
    _S + 'Mark Trees/Legacy/windchimes_fastAsc1.wav',
    _S + 'Mark Trees/Legacy/windchimes_slowDesc1.wav',
    _S + 'Suspended Cymbal 1/susCymb1_hit_*',
    _S + 'Suspended Cymbal 1/susCymb1_cresc_2s.wav',
    _S + 'Hi-Hat Cymbal/HiHat_HitC_*',
    _S + 'Cajon/Cajon_hit2_*',
    _S + 'Claps/Clap_rr*',
    _S + 'Shaker, Small/Mid_ShakerHighFaster_*',
    _S + 'Tambourine 1/Tamb1_Hit_*',
    _M + 'Snare Drum, Modern 2/Snare3M_HitSN_*',
    _M + 'Snare Drum, Modern 2/Snare3M_Xstick_*',
    _M + 'Bass Drum 1/*',
)
VCSL_ROOT = None  # set from --vcsl before anything renders


def vcsl_midi(name):
    """VCSL names put middle C at C3 — MEASURED 2026-10-29: every instrument
    sounded 1200 cents above its name read as scientific pitch."""
    m = re.match(r'([A-Ga-g])(#?)(-?\d+)$', name)
    return 12 * (int(m.group(3)) + 2) + _PC[m.group(1).upper()] + (1 if m.group(2) else 0)


class Bank:
    """One VCSL instrument articulation: its files by velocity layer, each
    pitched sample keyed by the note it was recorded at."""

    def __init__(self, folder, rx, layers=('',), pitched=False, autotune=False, max_s=2.0):
        self.folder, self.rx, self.layers = folder, re.compile(rx), layers
        self.pitched, self.autotune, self.max_s = pitched, autotune, max_s
        self._by_layer = None

    def _scan(self):
        if self._by_layer is None:
            root = os.path.join(VCSL_ROOT, self.folder)
            if not os.path.isdir(root):
                _fail(f'no VCSL folder {self.folder!r} under {VCSL_ROOT}; run `fetch` first')
            by = {}
            for fn in sorted(os.listdir(root)):
                m = self.rx.search(fn)
                if not m or not fn.lower().endswith('.wav'):
                    continue
                g = m.groupdict()
                layer = g.get('layer') or ''
                if layer not in self.layers:
                    continue
                note = vcsl_midi(g['note']) if self.pitched else None
                by.setdefault(layer, []).append((note, os.path.join(root, fn)))
            if not by:
                _fail(f'no sample in {self.folder!r} matches {self.rx.pattern!r}')
            self._by_layer = by
        return self._by_layer

    def pick(self, target, vel, seed):
        by = self._scan()
        present = [lay for lay in self.layers if lay in by]
        cands = by[present[min(len(present) - 1, int(vel * len(present)))]]
        if self.pitched:
            best = min(abs(n - target) for n, _ in cands)
            # On a tie the sample above is used: shifting down sounds better than up.
            note = max(n for n, _ in cands if abs(n - target) == best)
            cands = [c for c in cands if c[0] == note]
        note, path = cands[seed % len(cands)]
        return path, note


_DECODED = {}


def load_sample(path, max_s):
    """A VCSL WAV (16 or 24 bit, mono or stereo, 44.1 or 48 kHz) as float channels."""
    key = (path, max_s)
    if key not in _DECODED:
        with wave.open(path, 'rb') as w:
            sr, sw, ch = w.getframerate(), w.getsampwidth(), w.getnchannels()
            raw = w.readframes(min(w.getnframes(), int(max_s * sr)))
        if sw == 2:
            a = array('h', raw)
        elif sw == 3:
            b = bytearray(len(raw) // 3 * 4)
            b[1::4], b[2::4], b[3::4] = raw[0::3], raw[1::3], raw[2::3]
            a = array('i', bytes(b))
        else:
            _fail(f'{path}: {8 * sw}-bit audio is not read here')
        if sys.byteorder == 'big':
            a.byteswap()
        # Each recording is brought to its own peak: VCSL keeps its session
        # levels, 34 dB apart between a cross-stick and a kick. A velocity
        # layer then chooses the timbre and the mix sets the level.
        peak = max(max(a), -min(a)) or 1
        scale = 1.0 / peak
        left = array('f', (v * scale for v in a[0::ch]))
        right = array('f', (v * scale for v in a[1::ch])) if ch > 1 else left
        _DECODED[key] = (sr, left, right)
    return _DECODED[key]


def resample(x, ratio, n_out):
    """Read `x` every `ratio` samples (Catmull-Rom): a rate change and a pitch shift."""
    n_out = max(0, min(n_out, int((len(x) - 3) / ratio)))
    if ratio == 1.0:
        return array('f', x[:n_out])
    out = array('f', bytes(4 * n_out))
    for i in range(n_out):
        p = i * ratio
        k = int(p)
        t = p - k
        x0 = x[k - 1] if k else x[0]
        x1, x2, x3 = x[k], x[k + 1], x[k + 2]
        out[i] = x1 + 0.5 * t * (x2 - x0 + t * (2 * x0 - 5 * x1 + 4 * x2 - x3
                                                + t * (3 * (x1 - x2) + x3 - x0)))
    return out


_CENTS = {}


def measured_cents(path, note, max_s):
    """How far a recording sits from its labelled pitch: a Hann-windowed DFT
    scanned ±80 cents around the label. VCSL's glockenspiel reads 8-24 cents
    sharp, one Đàn Tranh string 38, and the pianos' lower notes up to 10 flat —
    a stretch tuning that beats against the synthesised bass (MEASURED 2026-10-29)."""
    if path not in _CENTS:
        sr, left, right = load_sample(path, max_s)
        f = hz(note)
        a = int(0.08 * sr)
        n = min(int(min(0.6, max(0.25, 40.0 / f)) * sr), len(left) - a)
        seg = [(left[a + i] + right[a + i]) * (0.5 - 0.5 * math.cos(TAU * i / n)) for i in range(n)]

        def power(c):
            w = TAU * f * 2 ** (c / 1200.0) / sr
            re_, im = 0.0, 0.0
            for i in range(0, n, 2):
                re_ += seg[i] * math.cos(w * i)
                im += seg[i] * math.sin(w * i)
            return re_ * re_ + im * im
        best = max(range(-80, 81, 4), key=power)
        _CENTS[path] = max((best + d * 0.5 for d in range(-8, 9)), key=power)
    return _CENTS[path]


def _fade_tail(chans, n_fade):
    for ch in chans:
        n = len(ch)
        for i in range(max(0, n - n_fade), n):
            ch[i] *= (n - i) / n_fade


def sampled(f, dur, vel, seed, bank=None, release=0.3, ring=None):
    """A pitched VCSL note: nearest recorded note and velocity layer, shifted to
    pitch, held for `dur` (or `ring` seconds for a bar left to sound), then damped."""
    b = BANKS[bank]
    target = 69 + 12 * math.log2(f / 440.0)
    path, note = b.pick(target, vel, seed)
    sr, left, right = load_sample(path, b.max_s)
    cents = measured_cents(path, note, b.max_s) if b.autotune else 0.0
    ratio = 2 ** ((target - note - cents / 100.0) / 12.0) * sr / SR
    n_on = int((ring if ring is not None else dur) * SR)
    L = resample(left, ratio, n_on + int(release * SR))
    R = resample(right, ratio, len(L)) if right is not left else L
    k = math.exp(-1.0 / (release * 0.22 * SR))
    for ch in ((L,) if R is L else (L, R)):
        g = 1.0
        for t in range(min(n_on, len(ch)), len(ch)):
            g *= k
            ch[t] *= g
    _fade_tail((L,) if R is L else (L, R), int(0.01 * SR))
    return (L, R)


def hit(f, dur, vel, seed, bank=None, semis=0.0, lp_hz=None):
    """An unpitched VCSL one-shot (or a pitched gesture moved by `semis`)."""
    b = BANKS[bank]
    path, _ = b.pick(None, vel, seed)
    sr, left, right = load_sample(path, b.max_s)
    ratio = 2 ** (semis / 12.0) * sr / SR
    n = int(b.max_s * SR)
    L = resample(left, ratio, n)
    R = resample(right, ratio, n) if right is not left else array('f', L)
    if lp_hz:
        a = _lp_coef(lp_hz)
        for ch in (L, R):
            for _ in range(2):
                y = 0.0
                for i in range(len(ch)):
                    y += a * (ch[i] - y)
                    ch[i] = y
    _fade_tail((L, R), int(0.03 * SR))
    return (L, R)


def swell(f, dur, vel, seed, bank=None):
    """A recorded cymbal crescendo cut so its loudest moment is exactly `dur`
    after the note starts — the beat a riser leads into."""
    L, R = hit(f, dur, vel, seed, bank=bank)
    win = int(0.01 * SR)
    peak, best = 0, -1.0
    for s in range(0, len(L) - win, win):
        e = sum(abs(L[i]) + abs(R[i]) for i in range(s, s + win, 4))
        if e > best:
            best, peak = e, s + win
    n = int(dur * SR)
    start = peak - n
    outs = []
    for ch in (L, R):
        o = array('f', bytes(4 * n))
        for i in range(max(0, -start), n):
            o[i] = ch[start + i]
        outs.append(o)
    _fade_tail(outs, int(0.008 * SR))
    return tuple(outs)


_N = r'(?P<note>[A-Ga-g]#?-?\d)'
BANKS = {
    'upright': Bank(_Z + 'Upright Piano, Yamaha/Sustains', r'Sus_' + _N + r'_vl(?P<layer>\d)_rr1',
                    ('2', '3'), pitched=True, autotune=True, max_s=7.0),
    'grand': Bank(_Z + 'Grand Piano, Kawai/Sustains', r'sus_' + _N + r'_v(?P<layer>\d)_rr1',
                  ('2', '3'), pitched=True, autotune=True, max_s=7.0),
    'vibes': Bank(_S + 'Vibraphone/Soft Mallets', r'soft_' + _N + r'_v(?P<layer>\d)_rr',
                  ('1', '2'), pitched=True, max_s=5.0),
    'marimba': Bank(_S + 'Marimba', r'Outrigger_' + _N + r'_(?P<layer>soft|med|loud)_',
                    ('soft', 'med', 'loud'), pitched=True, max_s=3.0),
    'glock': Bank(_S + 'Glockenspiel', r'glock_(?P<layer>soft|medium|loud)_' + _N + r'_',
                  ('soft', 'medium', 'loud'), pitched=True, autotune=True, max_s=4.0),
    'chimes_up': Bank(_S + 'Mark Trees/Legacy', r'windchimes_fastAsc1', max_s=5.0),
    'chimes_down': Bank(_S + 'Mark Trees/Legacy', r'windchimes_slowDesc1', max_s=7.0),
    'cymbal': Bank(_S + 'Suspended Cymbal 1', r'susCymb1_hit_(?P<layer>pp|mp|fff|f)\d\.wav',
                   ('pp', 'mp', 'f', 'fff'), max_s=5.0),
    'cymbal_swell': Bank(_S + 'Suspended Cymbal 1', r'susCymb1_cresc_2s', max_s=5.0),
    'hh': Bank(_S + 'Hi-Hat Cymbal', r'HiHat_HitC_v(?P<layer>\d)_rr', ('1', '2', '3', '4'), max_s=0.6),
    'xstick': Bank(_M + 'Snare Drum, Modern 2', r'Xstick_v2_rr', max_s=0.6),
    'snare': Bank(_M + 'Snare Drum, Modern 2', r'HitSN_v(?P<layer>\d)_rr', ('2', '3', '4', '5'),
                  max_s=1.2),
    'cajon_bass': Bank(_S + 'Cajon', r'hit2_(?P<layer>pp|mp|f)_rr', ('pp', 'mp', 'f'), max_s=0.8),
    'claps': Bank(_S + 'Claps', r'^Clap_rr', max_s=0.8),
    'shaker_dn': Bank(_S + 'Shaker, Small', r'ShakerHighFaster_Down_rr', max_s=0.4),
    'shaker_up': Bank(_S + 'Shaker, Small', r'ShakerHighFaster_Up_rr', max_s=0.4),
    'tamb': Bank(_S + 'Tambourine 1', r'Tamb1_Hit_v(?P<layer>\d)_rr', ('1', '2'), max_s=0.8),
    'bass_drum': Bank(_M + 'Bass Drum 1', r'BDrumNew_hit_v(?P<layer>\d)_rr', ('2', '3', '5', '7'),
                      max_s=2.5),
}


# name: (render function, its options, mix gain, seed variants, is a drum)
INST = {
    'bass': (bass, {}, 0.46, 1, False),
    'sub': (bass, dict(bright=0.12, attack=0.03), 0.50, 1, False),
    'pluck': (pluck_lead, {}, 0.83, 2, False),
    'kick': (kick, {}, 0.70, 4, True),
    'kick_pop': (kick, dict(f_start=160.0, f_end=50.0, decay=0.3, click=0.08, drive=1.3), 0.51, 4, True),
    'upright': (sampled, dict(bank='upright', release=0.35), 0.70, 1, False),
    'grand': (sampled, dict(bank='grand', release=0.4), 1.0, 1, False),
    'vibes': (sampled, dict(bank='vibes', release=0.5), 0.6, 1, False),
    'marimba': (sampled, dict(bank='marimba', release=0.2, ring=1.2), 0.86, 1, False),
    'glock': (sampled, dict(bank='glock', release=0.4, ring=1.6), 1.3, 1, False),
    'chimes_up': (hit, dict(bank='chimes_up'), 1.4, 1, False),
    'chimes_down': (hit, dict(bank='chimes_down'), 1.4, 1, False),
    'cymbal': (hit, dict(bank='cymbal'), 1.25, 1, True),
    'cymbal_swell': (swell, dict(bank='cymbal_swell'), 1.0, 1, True),
    'hh': (hit, dict(bank='hh', lp_hz=9000.0), 1.4, 2, True),
    'xstick': (hit, dict(bank='xstick'), 2.0, 2, True),
    'snare': (hit, dict(bank='snare'), 2.0, 2, True),
    'cajon_bass': (hit, dict(bank='cajon_bass'), 2.0, 2, True),
    'claps': (hit, dict(bank='claps'), 2.8, 6, True),
    'shaker_dn': (hit, dict(bank='shaker_dn'), 1.4, 2, True),
    'shaker_up': (hit, dict(bank='shaker_up'), 1.4, 2, True),
    'tamb': (hit, dict(bank='tamb'), 1.0, 1, True),
    'bass_drum': (hit, dict(bank='bass_drum'), 1.6, 2, True),
}


# ---------------------------------------------------------------- composition

class Section:
    """One loop or one-shot: a list of notes on the style's beat grid."""

    def __init__(self, style, name, bars, loop, tail_s, anchor_beats, lp_hz):
        self.style, self.name, self.bars = style, name, bars
        self.loop, self.tail_s, self.anchor_beats, self.lp_hz = loop, tail_s, anchor_beats, lp_hz
        self.beat_s = 60.0 / style.bpm
        self.rng = random.Random(f'{style.name}/{name}')
        self.notes = []

    def n(self, beat, inst, pitch=None, dur=0.5, vel=0.8, pan=0.0, send=0.15):
        """A note. Straight time — no swing — with a few milliseconds of a
        player's looseness and a little variation in how hard."""
        jitter = self.rng.gauss(0.0, 0.002 if INST[inst][4] else 0.004) / self.beat_s
        vel = vel * (1.0 + self.rng.uniform(-0.05, 0.05))
        self.notes.append((beat + jitter, inst, pitch, dur, vel, pan, send))

    def chord(self, beat, inst, pitches, dur, vel, roll_s=0.012, pan=0.0, send=0.2):
        step = roll_s / self.beat_s
        for i, p in enumerate(pitches):
            self.n(beat + i * step, inst, p, max(0.05, dur - i * step), vel * (1.0 - 0.04 * i),
                   pan, send)


class Style:
    def __init__(self, name, title, bpm, key, room=0.6, damp=0.5, wet=0.7):
        assert (SR * 60) % bpm == 0, f'{bpm} BPM is not a whole number of samples per beat'
        self.name, self.title, self.bpm = name, title, bpm
        self.key = _PC[key[0]] + (1 if key[1:] == '#' else -1 if key[1:] == 'b' else 0)
        self.room, self.damp, self.wet = room, damp, wet
        self.sections = {}

    def sec(self, name, bars, loop=True, tail_s=0.0, anchor_beats=0.0, lp_hz=None):
        s = Section(self, name, bars, loop, tail_s, anchor_beats, lp_hz)
        self.sections[name] = s
        return s


def check_melody(st, prog, melody):
    """Rule 1 of the module docstring, enforced: every note is in the key; a note
    on beat 1 or 3 of its bar, or held a beat or longer, is a tone of the bar's
    chord; and no note runs over a bar line. A breach refuses to render."""
    scale = {(st.key + s) % 12 for s in MAJOR}
    for beat, dur, nm in melody:
        pc = midi(nm) % 12
        bar = int(beat // 4)
        pos = beat - 4 * bar
        here = f'{st.name}: {nm} at beat {beat}'
        if pc not in scale:
            _fail(f'{here} is outside the key')
        name = prog[bar % len(prog)]
        if (abs(pos) < 1e-9 or abs(pos - 2) < 1e-9 or dur >= 1.0) and pc not in triad(name):
            _fail(f'{here} is not a tone of {name}')
        if beat + dur > 4 * (bar + 1) + 1e-9:
            _fail(f'{here} runs over its bar line')


def _phrase(bars):
    """Notes given bar by bar as (beat in bar, beats, note) -> one timeline."""
    return [(4 * i + b, d, nm) for i, bar in enumerate(bars) for b, d, nm in bar]


def _build(st, prog, melody, *, lead, shift, chords, bass_line, drums, hit_kick, outro,
           intro_lp=None):
    """The same five-part shape for every style, so they differ only in what
    they play: intro (chords), travel_a (drums, bass, chords, the hook),
    travel_b (fuller drums, the hook and its answer), stop (chords and the
    whole tune, softly)."""
    check_melody(st, prog, melody)

    def tune(s, notes, vel):
        for b, d, nm in notes:
            s.n(b, lead, midi(nm) + shift, d * 0.95, vel, 0.05, 0.25)

    s = st.sec('intro', 4, lp_hz=intro_lp)
    chords(s, 'soft')
    s = st.sec('travel_a', 4)
    drums(s, False)
    bass_line(s)
    chords(s, 'drive')
    tune(s, [m for m in melody if m[0] < 16], 0.75)
    s = st.sec('travel_b', 8)
    drums(s, True)
    bass_line(s)
    chords(s, 'drive')
    tune(s, melody, 0.8)
    s = st.sec('stop', 8)
    chords(s, 'soft')
    tune(s, melody, 0.65)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    s.n(0, 'cymbal_swell', None, 4, 0.6, 0.0, 0.25)
    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'cymbal', None, 4, 0.5, 0.1, 0.3)
    s.n(0, hit_kick, None, 1, 0.9, 0.0, 0.1)
    s = st.sec('hit_soft', 1, loop=False, tail_s=3.5)
    s.n(0, 'chimes_up', None, 4, 0.5, 0.0, 0.3)
    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    outro(s)
    s.n(0.5, 'chimes_down', None, 4, 0.4, 0.0, 0.3)
    return st


def pop():
    """Open Road — bright pop, after Chiu's Polarsteps reference (measured
    2026-10-30: 118 BPM, E major, triads I iii vi IV V, four-on-the-floor kick,
    a short hook). I–V–vi–IV in E; piano and bass share one 3-3-2 rhythm; the
    hook is an electronic pluck."""
    st = Style('pop', 'Open Road', 120, 'E', room=0.5, wet=0.6)
    prog = ['E', 'B', 'C#m', 'A']
    V = voice(prog, midi('E3'))
    a = [[(0, .5, 'B4'), (.5, .5, 'G#4'), (1, .5, 'B4'), (1.5, .5, 'C#5'), (2, 1.5, 'B4'), (3.5, .5, 'G#4')],
         [(0, 1, 'D#5'), (1, .5, 'C#5'), (1.5, .5, 'B4'), (2, 1.5, 'F#4'), (3.5, .5, 'G#4')],
         [(0, .5, 'G#4'), (.5, .5, 'C#5'), (1, .5, 'E5'), (1.5, .5, 'D#5'), (2, 1.5, 'C#5'), (3.5, .5, 'B4')]]
    melody = _phrase(a + [[(0, 1, 'C#5'), (1, .5, 'B4'), (1.5, .5, 'A4'), (2, 2, 'E4')]]
                     + a + [[(0, .5, 'A4'), (.5, .5, 'B4'), (1, .5, 'C#5'), (1.5, .5, 'B4'), (2, 2, 'E5')]])

    def chords(s, how):
        for b in range(s.bars):
            v = V[b % 4]
            if how == 'soft':
                s.chord(b * 4, 'grand', v, 3.8, 0.7)
            else:
                for o, d in ((0, 1.4), (1.5, 1.4), (3, 0.9)):
                    s.chord(b * 4 + o, 'grand', v, d, 0.4)

    def bass_line(s):
        for b in range(s.bars):
            r = root_in(prog[b % 4], midi('A1'))
            for o, d in ((0, 1.3), (1.5, 1.3), (3, 0.8)):
                s.n(b * 4 + o, 'bass', r, d, 0.68, 0.0, 0.0)

    def drums(s, full):
        for b in range(s.bars):
            for k in range(4):
                s.n(b * 4 + k, 'kick_pop', None, 0.5, 0.8, 0.0, 0.05)
            for k in (1, 3):
                s.n(b * 4 + k, 'claps', None, 0.5, 0.78, 0.0, 0.2)
            if full:
                for k in (0.5, 1.5, 2.5, 3.5):
                    s.n(b * 4 + k, 'hh', None, 0.25, 0.56, 0.2, 0.1)

    def outro(s):
        s.chord(0, 'grand', [midi('E2'), midi('B2')] + V[0], 7, 0.55, roll_s=0.04)
        s.n(0, 'pluck', midi('E5'), 2, 0.6, 0.05, 0.25)

    return _build(st, prog, melody, lead='pluck', shift=0, chords=chords, bass_line=bass_line,
                  drums=drums, hit_kick='kick_pop', outro=outro)


def acoustic():
    """Sunny Walk — warm folk-pop: an upright piano keeping time in quarters,
    cajón and claps, a glockenspiel tune. I–IV–vi–V in G."""
    st = Style('acoustic', 'Sunny Walk', 100, 'G', room=0.55, wet=0.65)
    prog = ['G', 'C', 'Em', 'D']
    V = voice(prog, midi('D3'))
    melody = _phrase([
        [(0, 1, 'D5'), (1, .5, 'B4'), (1.5, .5, 'D5'), (2, 1.5, 'G5'), (3.5, .5, 'A5')],
        [(0, 1.5, 'G5'), (1.5, .5, 'E5'), (2, 1.5, 'E5'), (3.5, .5, 'D5')],
        [(0, 1, 'E5'), (1, .5, 'G5'), (1.5, .5, 'F#5'), (2, 1.5, 'B4'), (3.5, .5, 'D5')],
        [(0, 1.5, 'D5'), (1.5, .5, 'E5'), (2, 2, 'F#5')],
        [(0, 1, 'D5'), (1, .5, 'B4'), (1.5, .5, 'D5'), (2, 1.5, 'B5'), (3.5, .5, 'A5')],
        [(0, 1.5, 'G5'), (1.5, .5, 'E5'), (2, 1.5, 'C5'), (3.5, .5, 'D5')],
        [(0, 1, 'E5'), (1, 1, 'G5'), (2, 1.5, 'B5'), (3.5, .5, 'A5')],
        [(0, 1, 'F#5'), (1, 1, 'A5'), (2, 2, 'D5')]])

    def chords(s, how):
        for b in range(s.bars):
            v = V[b % 4]
            if how == 'soft':
                s.chord(b * 4, 'upright', v, 3.8, 0.8, roll_s=0.03)
            else:
                for k, vel in enumerate((0.55, 0.38, 0.47, 0.38)):
                    s.chord(b * 4 + k, 'upright', v, 0.9, vel)

    def bass_line(s):
        for b in range(s.bars):
            r = root_in(prog[b % 4], midi('A1'))
            s.n(b * 4, 'bass', r, 1.8, 0.7, 0.0, 0.0)
            s.n(b * 4 + 2, 'bass', r, 1.8, 0.58, 0.0, 0.0)

    def drums(s, full):
        for b in range(s.bars):
            for k in (0, 2):
                s.n(b * 4 + k, 'cajon_bass', None, 0.5, 0.95, 0.0, 0.12)
            for k in (1, 3):
                s.n(b * 4 + k, 'claps', None, 0.5, 0.87, 0.0, 0.2)
            if full:
                for k in (0.5, 1.5, 2.5, 3.5):
                    s.n(b * 4 + k, 'tamb', None, 0.25, 0.48, 0.25, 0.12)

    def outro(s):
        s.chord(0, 'upright', [midi('G2'), midi('D3')] + V[0], 7, 0.6, roll_s=0.04)
        s.n(0.5, 'glock', midi('G6'), 2, 0.4, -0.2, 0.3)

    return _build(st, prog, melody, lead='glock', shift=12, chords=chords, bass_line=bass_line,
                  drums=drums, hit_kick='cajon_bass', outro=outro)


def cinematic():
    """Northern Light — one grand piano, as a pianist plays it: the left hand
    rolling through root, fifth and third, the right hand singing. A soft bass
    drum, a half-time snare once it drives. I–V–vi–IV in D."""
    st = Style('cinematic', 'Northern Light', 80, 'D', room=0.85, damp=0.35, wet=0.9)
    prog = ['D', 'A', 'Bm', 'G']
    melody = _phrase([
        [(0, 1, 'A4'), (1, .5, 'F#4'), (1.5, .5, 'G4'), (2, 2, 'A4')],
        [(0, 1, 'C#5'), (1, .5, 'B4'), (1.5, .5, 'A4'), (2, 2, 'E5')],
        [(0, 1, 'D5'), (1, .5, 'C#5'), (1.5, .5, 'D5'), (2, 2, 'F#5')],
        [(0, 1.5, 'D5'), (1.5, .5, 'C#5'), (2, 2, 'B4')],
        [(0, 1, 'A4'), (1, .5, 'F#4'), (1.5, .5, 'G4'), (2, 2, 'A4')],
        [(0, 1, 'C#5'), (1, .5, 'D5'), (1.5, .5, 'E5'), (2, 2, 'A5')],
        [(0, 1.5, 'F#5'), (1.5, .5, 'E5'), (2, 2, 'D5')],
        [(0, 1.5, 'B4'), (1.5, .5, 'C#5'), (2, 2, 'D5')]])

    def chords(s, how):
        vel = 0.35 if how == 'soft' else 0.45
        for b in range(s.bars):
            name = prog[b % 4]
            r = root_in(name, midi('A1'))
            third = (triad(name)[1] - triad(name)[0]) % 12
            for i, iv in enumerate((0, 7, 12, 12 + third, 19, 12 + third, 12, 7)):
                s.n(b * 4 + i * 0.5, 'grand', r + iv, 1.5, vel * (1.2 if i == 0 else 1.0), -0.15, 0.4)

    def bass_line(s):
        for b in range(s.bars):
            s.n(b * 4, 'sub', root_in(prog[b % 4], midi('A1')), 3.8, 0.5, 0.0, 0.0)

    def drums(s, full):
        for b in range(s.bars):
            s.n(b * 4, 'bass_drum', None, 1, 0.55 if full else 0.4, 0.0, 0.3)
            if full:
                s.n(b * 4 + 2.5, 'bass_drum', None, 1, 0.3, 0.0, 0.3)
                s.n(b * 4 + 2, 'snare', None, 0.5, 0.76, 0.0, 0.45)

    def outro(s):
        s.chord(0, 'grand', chord_notes('D2 A2 D3 F#3 A3 D4 F#4'), 8, 0.6, roll_s=0.05, send=0.5)

    return _build(st, prog, melody, lead='grand', shift=0, chords=chords, bass_line=bass_line,
                  drums=drums, hit_kick='bass_drum', outro=outro)


def lofi():
    """Neon Rain — lo-fi, kept plain: an upright piano, a vibraphone tune, a soft
    kick and a cross-stick. IV–V–iii–vi in C, the 'royal road' progression of
    Japanese pop."""
    st = Style('lofi', 'Neon Rain', 84, 'C', room=0.55, wet=0.7)
    prog = ['F', 'G', 'Em', 'Am']
    V = voice(prog, midi('E3'))
    melody = _phrase([
        [(0, 1, 'A4'), (1, .5, 'G4'), (1.5, .5, 'A4'), (2, 1.5, 'C5'), (3.5, .5, 'D5')],
        [(0, 1.5, 'B4'), (1.5, .5, 'A4'), (2, 2, 'G4')],
        [(0, 1, 'G4'), (1, .5, 'A4'), (1.5, .5, 'B4'), (2, 1.5, 'E5'), (3.5, .5, 'D5')],
        [(0, 2, 'C5'), (2, 1, 'A4'), (3, 1, 'E4')],
        [(0, 1, 'A4'), (1, .5, 'G4'), (1.5, .5, 'A4'), (2, 1.5, 'F5'), (3.5, .5, 'E5')],
        [(0, 1.5, 'D5'), (1.5, .5, 'C5'), (2, 2, 'B4')],
        [(0, 1, 'G4'), (1, .5, 'A4'), (1.5, .5, 'B4'), (2, 1.5, 'G5'), (3.5, .5, 'E5')],
        [(0, 1.5, 'E5'), (1.5, .5, 'D5'), (2, 2, 'C5')]])

    def chords(s, how):
        for b in range(s.bars):
            v = V[b % 4]
            if how == 'soft':
                s.chord(b * 4, 'upright', v, 3.8, 0.9, roll_s=0.03)
            else:
                s.chord(b * 4, 'upright', v, 2.4, 0.7)
                s.chord(b * 4 + 2.5, 'upright', v, 1.4, 0.53)

    def bass_line(s):
        for b in range(s.bars):
            r = root_in(prog[b % 4], midi('A1'))
            s.n(b * 4, 'bass', r, 2.2, 0.85, 0.0, 0.0)
            s.n(b * 4 + 2.5, 'bass', r, 1.2, 0.65, 0.0, 0.0)

    def drums(s, full):
        for b in range(s.bars):
            for k, v in ((0, 0.75), (2.5, 0.6)):
                s.n(b * 4 + k, 'kick', None, 0.5, v, 0.0, 0.05)
            for k in (1, 3):
                s.n(b * 4 + k, 'xstick', None, 0.5, 0.95, 0.05, 0.18)
            if full:
                for i in range(8):
                    s.n(b * 4 + i * 0.5, 'hh', None, 0.25, 0.5 if i % 2 == 0 else 0.33, 0.2, 0.1)

    def outro(s):
        s.chord(0, 'upright', chord_notes('C2 G2') + voice(['C'], midi('E3'))[0], 7, 0.6, roll_s=0.04)
        s.n(0.5, 'vibes', midi('E5'), 3, 0.5, 0.2, 0.3)

    return _build(st, prog, melody, lead='vibes', shift=0, chords=chords, bass_line=bass_line,
                  drums=drums, hit_kick='kick', outro=outro)


def tropical():
    """Coconut Road — light tropical: off-beat piano stabs, a marimba tune, a
    soft four-on-the-floor kick and a shaker. vi–IV–I–V in C (A minor's
    colour), the tropical-house progression."""
    st = Style('tropical', 'Coconut Road', 105, 'C', room=0.6, wet=0.65)
    prog = ['Am', 'F', 'C', 'G']
    V = voice(prog, midi('C4'))
    a = [[(0, .5, 'E5'), (.5, .5, 'C5'), (1, .5, 'E5'), (1.5, .5, 'G5'), (2, 1, 'A5'), (3, 1, 'E5')],
         [(0, .5, 'F5'), (.5, .5, 'C5'), (1, .5, 'F5'), (1.5, .5, 'G5'), (2, 1, 'A5'), (3, 1, 'F5')],
         [(0, .5, 'E5'), (.5, .5, 'C5'), (1, .5, 'E5'), (1.5, .5, 'G5'), (2, 1, 'C6'), (3, 1, 'G5')]]
    melody = _phrase(a + [[(0, .5, 'D5'), (.5, .5, 'B4'), (1, .5, 'D5'), (1.5, .5, 'E5'), (2, 2, 'G5')]]
                     + a + [[(0, .5, 'B4'), (.5, .5, 'D5'), (1, .5, 'G5'), (1.5, .5, 'A5'), (2, 2, 'B5')]])

    def chords(s, how):
        for b in range(s.bars):
            v = V[b % 4]
            if how == 'soft':
                s.chord(b * 4, 'grand', v, 3.8, 0.6, roll_s=0.03)
            else:
                for k in (0.5, 1.5, 2.5, 3.5):
                    s.chord(b * 4 + k, 'grand', v, 0.35, 0.31, roll_s=0.006)

    def bass_line(s):
        for b in range(s.bars):
            r = root_in(prog[b % 4], midi('A1'))
            s.n(b * 4, 'bass', r, 1.8, 0.76, 0.0, 0.0)
            s.n(b * 4 + 2, 'bass', r, 1.8, 0.62, 0.0, 0.0)

    def drums(s, full):
        for b in range(s.bars):
            for k in range(4):
                s.n(b * 4 + k, 'kick', None, 0.5, 0.55, 0.0, 0.05)
            for k in (1, 3):
                s.n(b * 4 + k, 'claps', None, 0.5, 0.75, 0.0, 0.2)
            if full:
                for i in range(8):
                    s.n(b * 4 + i * 0.5, 'shaker_dn' if i % 2 == 0 else 'shaker_up', None, 0.25,
                        0.48 if i % 2 else 0.34, -0.25, 0.1)

    def outro(s):
        s.chord(0, 'grand', chord_notes('A1 E2') + voice(['Am'], midi('C4'))[0], 7, 0.55, roll_s=0.04)
        s.n(0.5, 'marimba', midi('A5'), 1, 0.6, -0.2, 0.3)

    return _build(st, prog, melody, lead='marimba', shift=0, chords=chords, bass_line=bass_line,
                  drums=drums, hit_kick='kick', outro=outro)


def chord_notes(names):
    return [midi(x) for x in names.split()]


STYLES = {'pop': pop, 'acoustic': acoustic, 'cinematic': cinematic, 'lofi': lofi,
          'tropical': tropical}
# Chiu's region table of 2026-10-29, carried onto the moods that fit it. Pop has
# no countries yet: whether it is what every other country gets is Chiu's call.
COUNTRIES = {'lofi': ('JP', 'TW', 'KR'), 'cinematic': ('IS', 'NO'), 'tropical': ('VN', 'TH'),
             'acoustic': ('NZ', 'AU'), 'pop': ()}
LOOPS = ('intro', 'travel_a', 'travel_b', 'stop')
ONE_SHOTS = ('riser', 'hit_big', 'hit_soft', 'outro')


def style_for_country(code):
    for name, codes in COUNTRIES.items():
        if code.upper() in codes:
            return name
    return None


# ---------------------------------------------------------------- rendering

COMBS = (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
ALLPASSES = (556, 441, 341, 225)


def freeverb(send, room, damp, circular, predelay_s=0.02):
    """Stereo Freeverb. A loop's input is fed twice and the second pass kept,
    so the reverb's tail from the end of the loop is already in its start."""
    n = len(send)
    pd = int(predelay_s * SR)
    if circular:
        rot = send[n - pd:] + send[:n - pd]
        x = rot + rot
    else:
        x = zeros(pd) + send[:n - pd]
    fb = room * 0.28 + 0.7
    d1 = damp * 0.4
    d2 = 1.0 - d1
    gain_in = 0.015
    norm = math.sqrt(1.0 - fb * fb) / (math.sqrt(len(COMBS)) * gain_in)
    m = len(x)
    xin = array('d', (v * gain_in for v in x))
    outs = []
    for spread in (0, 23):
        acc = zeros(m)
        for d0 in COMBS:
            d = d0 + spread
            buf = [0.0] * d
            i, store = 0, 0.0
            for t in range(m):
                o = buf[i]
                store = o * d2 + store * d1
                buf[i] = xin[t] + store * fb
                i += 1
                if i == d:
                    i = 0
                acc[t] += o
        for d0 in ALLPASSES:
            d = d0 + spread
            buf = [0.0] * d
            i = 0
            for t in range(m):
                b = buf[i]
                v = acc[t]
                buf[i] = v + b * 0.5
                acc[t] = b - v
                i += 1
                if i == d:
                    i = 0
        if circular:
            acc = acc[n:]
        for t in range(n):
            acc[t] *= norm
        outs.append(acc)
    return outs


def lowpass(buf, fc, circular):
    """Two one-pole low-passes; a loop is run twice so it wraps cleanly."""
    a = _lp_coef(fc)
    n = len(buf)
    for _ in range(2):
        out = zeros(n)
        y = 0.0
        for p in range(2 if circular else 1):
            for i in range(n):
                y += a * (buf[i] - y)
                out[i] = y
        buf = out
    return buf


def place(dl, dr, ds, sig, start, gl, gr, gs, circular):
    """Add a note into the section: a mono signal is panned, a stereo
    recording (a (left, right) pair) keeps its own image and is balanced."""
    stereo = isinstance(sig, tuple)
    sl, sr = sig if stereo else (sig, sig)
    gsh = gs * 0.5 if stereo else gs
    n, total = len(sl), len(dl)
    spans = []
    if circular:
        pos, j0 = 0, start % total
        while pos < n:
            m = min(n - pos, total - j0)
            spans.append((pos, j0, m))
            pos += m
            j0 = 0
    else:
        k0 = max(0, -start)
        spans.append((k0, start + k0, max(0, min(n, total - start) - k0)))
    for pos, j0, m in spans:
        if stereo:
            for k in range(m):
                a, b = sl[pos + k], sr[pos + k]
                j = j0 + k
                dl[j] += a * gl
                dr[j] += b * gr
                ds[j] += (a + b) * gsh
        else:
            for k in range(m):
                v = sl[pos + k]
                j = j0 + k
                dl[j] += v * gl
                dr[j] += v * gr
                ds[j] += v * gsh


def render_section(st, sec, cache):
    beat_n = SR * 60 // st.bpm
    body = sec.bars * 4 * beat_n
    n = body if sec.loop else body + int(sec.tail_s * SR)
    dl, dr, ds = zeros(n), zeros(n), zeros(n)
    for beat, inst, pitch, dur, vel, pan, send in sec.notes:
        fn, opts, gain, variants, _ = INST[inst]
        vq = round(min(1.0, max(0.02, vel)) * 20) / 20
        seed = sec.rng.randrange(variants)
        dur_s = dur * sec.beat_s
        key = (inst, pitch, round(dur_s, 3), vq, seed)
        sig = cache.get(key)
        if sig is None:
            sig = fn(hz(pitch) if pitch is not None else 0.0, dur_s, vq, seed, **opts)
            cache[key] = sig
        amp = gain * vq
        theta = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi / 4.0
        place(dl, dr, ds, sig, int(round(beat * beat_n)), amp * math.cos(theta),
              amp * math.sin(theta), amp * send, sec.loop)
    wl, wr = freeverb(ds, st.room, st.damp, sec.loop)
    for i in range(n):
        dl[i] += wl[i] * st.wet
        dr[i] += wr[i] * st.wet
    if sec.lp_hz:
        dl, dr = lowpass(dl, sec.lp_hz, sec.loop), lowpass(dr, sec.lp_hz, sec.loop)
    return dl, dr


def write_wav(path, left, right):
    n = len(left)
    pcm = array('h', bytes(4 * n))
    for i in range(n):
        pcm[2 * i] = int(round(max(-1.0, min(1.0, left[i])) * 32767))
        pcm[2 * i + 1] = int(round(max(-1.0, min(1.0, right[i])) * 32767))
    if sys.byteorder == 'big':
        pcm.byteswap()
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, 'rb') as w:
        assert w.getnchannels() == 2 and w.getsampwidth() == 2 and w.getframerate() == SR, path
        pcm = array('h', w.readframes(w.getnframes()))
    if sys.byteorder == 'big':
        pcm.byteswap()
    return array('d', (v / 32767 for v in pcm[0::2])), array('d', (v / 32767 for v in pcm[1::2]))


# Every style's driving loop sits at one loudness, so a film in Iceland and a
# film in Vietnam play at the same level; the peak cap leaves room for a hit.
TRAVEL_RMS_DBFS = -20.0
PEAK_CAP = 0.8


def use_vcsl(root):
    global VCSL_ROOT
    VCSL_ROOT = root
    lic = os.path.join(root, 'LICENSE')
    if not os.path.exists(lic) or 'CC0 1.0 Universal' not in open(lic, errors='replace').read():
        _fail(f'{root} is not a VCSL checkout under CC0 1.0; run `fetch` first')


def render_style(name, out_root, vcsl_root):
    use_vcsl(vcsl_root)
    st = STYLES[name]()
    beat_n = SR * 60 // st.bpm
    cache = {}
    rendered = {k: render_section(st, s, cache) for k, s in st.sections.items()}
    peak = max(max(abs(v) for v in ch) for lr in rendered.values() for ch in lr)
    tl, tr = rendered['travel_b']
    rms = math.sqrt((sum(v * v for v in tl) + sum(v * v for v in tr)) / (2 * len(tl)))
    scale = min(10 ** (TRAVEL_RMS_DBFS / 20) / rms, PEAK_CAP / peak)
    out = os.path.join(out_root, name)
    os.makedirs(out, exist_ok=True)
    levels = {}
    for k, (left, right) in rendered.items():
        for ch in (left, right):
            for i in range(len(ch)):
                ch[i] *= scale
        write_wav(os.path.join(out, f'{k}.wav'), left, right)
        rms = math.sqrt(sum(v * v for v in left) / len(left))
        levels[k] = round(20 * math.log10(max(rms, 1e-9)), 1)
    beatmap = {
        'style': name, 'title': st.title, 'countries': list(COUNTRIES[name]),
        'sample_rate': SR, 'bpm': st.bpm, 'beats_per_bar': 4, 'beat_samples': beat_n,
        'progression_bars': 4,
        'loops': {k: {'file': f'{k}.wav', 'bars': st.sections[k].bars,
                      'samples': st.sections[k].bars * 4 * beat_n} for k in LOOPS},
        'one_shots': {k: {'file': f'{k}.wav',
                          'anchor_samples': int(round(st.sections[k].anchor_beats * beat_n))}
                      for k in ONE_SHOTS},
        'samples': {'library': 'VCSL (Versilian Studios), CC0 1.0', 'url': VCSL_URL,
                    'commit': VCSL_COMMIT},
        'rms_dbfs_left': levels,
    }
    with open(os.path.join(out, 'beatmap.json'), 'w') as f:
        json.dump(beatmap, f, indent=2)
        f.write('\n')
    return name, out, levels


# ---------------------------------------------------------------- arranging

# kind: (loop after it, riser into it, hit on it, seconds the old loop fades over)
RECIPES = {
    'go': ('travel', True, 'hit_big', 0.12),
    'crossing': ('travel_b', True, 'hit_big', 0.12),
    'stop': ('stop', False, 'hit_soft', 0.9),
    'end': (None, True, None, 0.35),
}

# Illustrative, NOT measured from a render: roughly a short film's shape at the
# shipped pacing (6.5 s opening, 2.5 s a photo, a 4.0 s crossing card).
EXAMPLE_TIMELINE = {
    'duration_s': 64.0,
    'events': [
        {'t': 6.5, 'kind': 'go'}, {'t': 14.2, 'kind': 'stop'}, {'t': 22.7, 'kind': 'go'},
        {'t': 29.6, 'kind': 'stop'}, {'t': 40.6, 'kind': 'go'}, {'t': 44.9, 'kind': 'crossing'},
        {'t': 53.1, 'kind': 'stop'}, {'t': 59.1, 'kind': 'end'},
    ],
}


def plan(timeline, beat_n):
    """Snap each event to the nearest beat and decide what plays after it."""
    dur_n = int(round(timeline['duration_s'] * SR))
    events = sorted(timeline['events'], key=lambda e: e['t'])
    cues, last_travel, prev = [], None, -1
    for e in events:
        kind, t = e['kind'], float(e['t'])
        if kind not in RECIPES:
            _fail(f'unknown event kind {kind!r}; kinds are {", ".join(RECIPES)}')
        if not 0 <= t <= timeline['duration_s']:
            _fail(f'{kind} at {t:.2f}s is outside the film (0–{timeline["duration_s"]}s)')
        if cues and cues[-1]['kind'] == 'end':
            _fail(f'{kind} at {t:.2f}s comes after the end card')
        k = int(round(t * SR / beat_n))
        if k <= prev:
            _fail(f'{kind} at {t:.2f}s lands on the same beat as the event before it '
                  f'(beat {k}); the music cannot change twice on one beat')
        prev = k
        nxt = RECIPES[kind][0]
        if nxt == 'travel':
            nxt = 'travel_b' if last_travel == 'travel_a' else 'travel_a'
        if nxt in ('travel_a', 'travel_b'):
            last_travel = nxt
        at = k * beat_n
        cues.append({'kind': kind, 't_s': round(t, 3), 'beat_t_s': round(at / SR, 3),
                     'shift_ms': round((at / SR - t) * 1000), 'bar': k // 4 + 1, 'beat': k % 4 + 1,
                     'plays': nxt or 'outro', 'at': at})
    return dur_n, cues


def arrange(music_dir, timeline):
    with open(os.path.join(music_dir, 'beatmap.json')) as f:
        bm = json.load(f)
    beat_n = bm['beat_samples']
    dur_n, cues = plan(timeline, beat_n)
    tail_n = int(6.0 * SR)
    n = dur_n + tail_n
    L, R = zeros(n), zeros(n)
    loops = {k: read_wav(os.path.join(music_dir, v['file'])) for k, v in bm['loops'].items()}
    shots = {k: read_wav(os.path.join(music_dir, v['file'])) for k, v in bm['one_shots'].items()}

    def add_loop(name, s0, s1, fade_in_n, fade_out_n):
        ll, lr = loops[name]
        size = len(ll)
        a, b = max(0, s0 - fade_in_n), min(n, s1 + fade_out_n)
        for j in range(a, b):
            g = 1.0
            if j < s0:
                g = (j - a + 1) / (s0 - a + 1)
            elif j >= s1:
                g = 1.0 - (j - s1) / max(1, fade_out_n)
            p = j % size
            L[j] += ll[p] * g
            R[j] += lr[p] * g

    def add_shot(name, at, floor):
        sl, sr = shots[name]
        start = at - bm['one_shots'][name]['anchor_samples']
        k0 = max(0, floor - start)
        ramp = int(0.015 * SR)
        for k in range(k0, min(len(sl), n - start)):
            g = min(1.0, (k - k0) / ramp) if k0 > 0 else 1.0
            L[start + k] += sl[k] * g
            R[start + k] += sr[k] * g

    current, seg_start, prev_at = 'intro', 0, 0
    first_fade = int(0.3 * SR)
    seg_fade_in = first_fade
    for c in cues:
        _, riser, hit, fade_s = RECIPES[c['kind']]
        at = c['at']
        if current:
            add_loop(current, seg_start, at, seg_fade_in, int(fade_s * SR))
        if riser:
            add_shot('riser', at, prev_at)
        if hit:
            add_shot(hit, at, 0)
        if c['kind'] == 'end':
            add_shot('outro', at, 0)
            current = None
        else:
            current = c['plays']
        seg_start, seg_fade_in, prev_at = at, int(0.008 * SR), at
    if current:
        add_loop(current, seg_start, dur_n, seg_fade_in, 0)

    fade = int(1.2 * SR)
    for j in range(max(0, dur_n - fade), n):
        g = max(0.0, (dur_n - j) / fade) if j < dur_n else 0.0
        L[j] *= g
        R[j] *= g
    # A soft ceiling at -0.7 dBFS, under the overshoot AAC adds when encoding.
    for ch in (L, R):
        for j in range(n):
            x = ch[j]
            a = abs(x)
            if a > 0.8:
                ch[j] = math.copysign(0.8 + 0.12 * math.tanh((a - 0.8) / 0.12), x)
    return L[:dur_n], R[:dur_n], cues


# ---------------------------------------------------------------- command line

def _default_out():
    return os.path.join(os.path.expanduser('~'), 'Kamome-music')


def fetch(dest):
    """Check out the pinned VCSL commit — only the paths the styles use."""
    def run(*cmd):
        print('+', ' '.join(cmd))
        if subprocess.run(cmd).returncode:
            _fail(f'`{" ".join(cmd)}` failed')
    if not os.path.isdir(os.path.join(dest, '.git')):
        os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
        run('git', 'clone', '--filter=blob:none', '--no-checkout', '--depth', '1', VCSL_URL, dest)
    git = ('git', '-C', dest)
    run(*git, 'sparse-checkout', 'set', '--no-cone', *('/' + p for p in VCSL_PATHS))
    run(*git, 'fetch', '--depth', '1', '--filter=blob:none', 'origin', VCSL_COMMIT)
    run(*git, 'checkout', '-q', '--detach', VCSL_COMMIT)
    use_vcsl(dest)
    print(f'VCSL {VCSL_COMMIT[:7]} (CC0 1.0) is at {dest}')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    vcsl_default = os.path.join(_default_out(), 'vcsl')
    fe = sub.add_parser('fetch', help='check out the VCSL recordings the styles use')
    fe.add_argument('--vcsl', default=vcsl_default)
    r = sub.add_parser('render', help='render loop sets')
    r.add_argument('--style', choices=STYLES, action='append')
    r.add_argument('--out', default=_default_out())
    r.add_argument('--vcsl', default=vcsl_default, help='where `fetch` put VCSL')
    a = sub.add_parser('arrange', help='arrange one style to a film timeline')
    a.add_argument('--style', choices=STYLES, required=True)
    g = a.add_mutually_exclusive_group(required=True)
    g.add_argument('--timeline', help='JSON: {"duration_s": .., "events": [{"t": .., "kind": ..}]}')
    g.add_argument('--example', action='store_true', help='an illustrative short-film timeline')
    a.add_argument('--music', default=_default_out(), help='where `render` wrote the styles')
    a.add_argument('--out', help='output .wav (default: <music>/<style>-arranged.wav)')
    c = sub.add_parser('style', help='which style a country gets')
    c.add_argument('--country', required=True, help='ISO 3166-1 alpha-2, e.g. IS')
    args = ap.parse_args()

    if args.cmd == 'fetch':
        fetch(args.vcsl)
    elif args.cmd == 'render':
        use_vcsl(args.vcsl)
        names = args.style or list(STYLES)
        with Pool(min(len(names), os.cpu_count() or 1)) as pool:
            jobs = [(nm, args.out, args.vcsl) for nm in names]
            for name, out, levels in pool.starmap(render_style, jobs):
                print(f'{name:15s} -> {out}   RMS dBFS (L): ' +
                      ', '.join(f'{k} {v}' for k, v in levels.items()))
    elif args.cmd == 'arrange':
        music = os.path.join(args.music, args.style)
        if not os.path.exists(os.path.join(music, 'beatmap.json')):
            _fail(f'no rendered {args.style} in {args.music}; run `render --style {args.style}` first')
        if args.example:
            timeline = EXAMPLE_TIMELINE
        else:
            with open(args.timeline) as f:
                timeline = json.load(f)
        left, right, cues = arrange(music, timeline)
        out = args.out or os.path.join(args.music, f'{args.style}-arranged.wav')
        write_wav(out, left, right)
        with open(os.path.splitext(out)[0] + '.cues.json', 'w') as f:
            json.dump([{k: v for k, v in c.items() if k != 'at'} for c in cues], f, indent=2)
            f.write('\n')
        print(f'{out}  ({timeline["duration_s"]:.1f}s)')
        print(f'  {"event":9s} {"film s":>7s} {"beat s":>7s} {"shift":>7s}  bar.beat  then')
        for c in cues:
            print(f'  {c["kind"]:9s} {c["t_s"]:7.2f} {c["beat_t_s"]:7.2f} {c["shift_ms"]:+5d}ms'
                  f'  {c["bar"]:3d}.{c["beat"]}     {c["plays"]}')
        worst = max((abs(c['shift_ms']) for c in cues), default=0)
        print(f'  largest shift {worst} ms — how far the film would move to land on the beat')
    else:
        name = style_for_country(args.country)
        if name is None:
            _fail(f'no style for {args.country.upper()}: only '
                  + ', '.join(f'{k} ({"/".join(v)})' for k, v in COUNTRIES.items() if v)
                  + ' are decided; what any other country gets is Chiu\'s call')
        print(name)


if __name__ == '__main__':
    main()
