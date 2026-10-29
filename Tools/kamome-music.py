#!/usr/bin/env python3
"""Kamome's own film music: four regional loop sets, composed here.

Why this exists (Chiu, 2026-10-29). The film is to have music, and only music
that is free to use. Free music that may be *bundled inside an app* and is not
registered with Content ID is a short list, so the music is written here.

**Where every sound comes from — the licence is the reason for each line:**

- **Acoustic instruments are CC0 1.0 recordings** from the Versilian Community
  Sample Library (VCSL, Versilian Studios): pianos, vibraphone, marimba,
  glockenspiel, Đàn Tranh, wind chimes and every drum and percussion sound.
  CC0 is a public-domain dedication — commercial use, no credit owed. Pinned to
  one commit (`VCSL_COMMIT`) so a render is repeatable. Chiu chose this on
  2026-10-29 over synthesised drums, which did not sit with the music.
- **Everything else is synthesised in this file** from sine waves and noise:
  the electric piano, basses, pads, flute, pan flute, whistle, kalimba and the
  steel and nylon guitars (VCSL has no guitar).

Nothing else goes in: no other sample, sound font or recording.

    python3 Tools/kamome-music.py fetch                     # the VCSL subset, once
    python3 Tools/kamome-music.py render                    # all four styles
    python3 Tools/kamome-music.py render --style nordic
    python3 Tools/kamome-music.py arrange --style nordic --example
    python3 Tools/kamome-music.py arrange --style nordic --timeline film.json
    python3 Tools/kamome-music.py style --country IS

`render` writes, per style, to `~/Kamome-music/<style>/` (or `--out`):

    intro.wav     loop      before the car moves (the title card)
    travel_a.wav  loop      driving
    travel_b.wav  loop      driving, fuller: after a stop, after a crossing
    stop.wav      loop      a stop's photos: no kick, no snare
    riser.wav     one-shot  leads into a transition; its anchor is the beat
    hit_big.wav   one-shot  the beat the car moves off or a crossing starts
    hit_soft.wav  one-shot  the beat a stop's photos open
    outro.wav     one-shot  the end card
    beatmap.json  tempo, loop lengths, one-shot anchors

**The beat map is exact, not detected**: the music is composed on its grid, and
each tempo is chosen so a beat is a whole number of samples at 44.1 kHz. The
grid never drifts against the audio.

**Why a loop can change on any beat.** Within a style every loop plays the same
4-bar chord progression and is a whole number of progressions long, and every
loop's phase is the film's clock. Bar k of every loop sits on the same chord,
so switching from one loop to another mid-phrase never clashes. Each style's
`stop` loop plays its travel melody's own theme, sparser, on another
instrument, so the film hears one tune throughout.

`arrange` takes a film's events — `{"duration_s": 64, "events": [{"t": 6.5,
"kind": "go"}, ...]}`, kinds `go` (the car moves), `stop` (a stop's photos
open), `crossing` (a crossing's card), `end` (the end card) — and writes one
soundtrack. Each event snaps to the nearest beat and the shift is printed: the
film is not moved here, which is the export's job once this is wired in. A riser
ends on the event's beat and a hit lands on it.

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


# ---------------------------------------------------------------- pitch

_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(name):
    """'F#4' -> 66, 'Bb1' -> 34 (scientific pitch: middle C is C4)."""
    pc, i = _PC[name[0]], 1
    while name[i] in '#b':
        pc += 1 if name[i] == '#' else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + pc


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def chord(names):
    return [midi(x) for x in names.split()]


def _lp_coef(fc):
    return 1.0 - math.exp(-TAU * fc / SR)


# ---------------------------------------------------------------- synthesised instruments
#
# Each takes (frequency in Hz, held seconds, velocity 0-1, seed) and returns a
# mono buffer that includes its own release. Only instruments that use noise
# read the seed; a note picks one of a few seeds, so repeated notes vary a
# little and still render identically on every run.

def ep(f, dur, vel, seed):
    """Electric piano: two FM pairs — a warm body, and a tine that dies fast."""
    n_on = int(dur * SR)
    n = n_on + int(0.4 * SR)
    out = zeros(n)
    w = TAU * f / SR
    k_amp = math.exp(-1.0 / (1.6 * (220.0 / f) ** 0.35 * SR))
    k_i1 = math.exp(-1.0 / (0.5 * SR))
    k_i2 = math.exp(-1.0 / (0.04 * SR))
    k_rel = math.exp(-1.0 / (0.08 * SR))
    att = int(0.004 * SR)
    amp, i1, i2, g = 1.0, 0.5 + 1.4 * vel, 1.4 * vel, 1.0
    sin = math.sin
    for t in range(n):
        ph = w * t
        y = 0.78 * sin(ph + (i1 + 0.2) * sin(ph)) + 0.22 * sin(ph + i2 * sin(14.0 * ph))
        e = amp * (t / att if t < att else 1.0)
        if t >= n_on:
            g *= k_rel
            e *= g
        out[t] = y * e
        amp *= k_amp
        i1 *= k_i1
        i2 *= k_i2
    return out


# A small acoustic guitar's body: (Hz, Q, gain) of its lowest air and top modes.
_BODY = ((102.0, 9.0, 0.5), (204.0, 11.0, 0.36), (296.0, 13.0, 0.24), (418.0, 15.0, 0.15))


def _body(x):
    """Ring a plucked string through the guitar body's resonances."""
    out = array('d', (v * 0.8 for v in x))
    for fc, q, g in _BODY:
        w0 = TAU * fc / SR
        alpha = math.sin(w0) / (2.0 * q)
        a0 = 1.0 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2.0 * math.cos(w0) / a0, (1.0 - alpha) / a0
        x1 = x2 = y1 = y2 = 0.0
        gg = g * 1.6
        for i in range(len(x)):
            xi = x[i]
            y = b0 * xi + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, xi, y1, y
            out[i] += gg * y
    return out


def pluck(f, dur, vel, seed, bright=0.5, t60=3.0, pick=0.14):
    """Plucked string: Karplus-Strong tuned with an all-pass, excited where a
    finger or pick would be (`pick` along the string), through a guitar body."""
    rng = random.Random(seed)
    n_on = int(dur * SR)
    n = n_on + int(0.15 * SR)
    p = SR / f - 0.5
    N = int(p)
    frac = p - N
    if frac < 0.1:
        N -= 1
        frac += 1.0
    C = (1.0 - frac) / (1.0 + frac)
    coef = min(1.0, bright * (0.6 + 0.4 * vel))
    raw = zeros(N)
    lp = 0.0
    for i in range(N):
        lp += coef * (rng.uniform(-1, 1) - lp)
        raw[i] = lp
    off = max(1, int(N * pick))
    line = array('d', (raw[i] - 0.8 * raw[(i + off) % N] for i in range(N)))
    mean = sum(line) / N
    peak = max(abs(v - mean) for v in line) or 1.0
    for i in range(N):
        line[i] = (line[i] - mean) / peak
    rho = 10.0 ** (-3.0 / (t60 * f))
    k_rel = math.exp(-1.0 / (0.025 * SR))
    out = zeros(n)
    w, y1, x1, a1, g = 0, 0.0, 0.0, 0.0, 1.0
    for t in range(n):
        y = line[w]
        fl = 0.5 * (y + y1)
        y1 = y
        ap = C * fl + x1 - C * a1
        x1, a1 = fl, ap
        line[w] = rho * ap
        w += 1
        if w == N:
            w = 0
        if t >= n_on:
            g *= k_rel
        out[t] = y * g
    return _body(out)


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


def pad(f, dur, vel, seed, attack=0.6, release=1.2, nh_cap=14, detune_c=7.0):
    """Pad: three detuned saws from a wavetable, slow in and slow out."""
    rng = random.Random(seed)
    n_on = int(dur * SR)
    n = n_on + int(release * SR)
    out = zeros(n)
    tab = _saw(max(1, min(nh_cap, int(NYQ_SAFE / (f * 1.01)))))
    att = max(1.0, attack * SR)
    k_rel = math.exp(-1.0 / (release * 0.3 * SR))
    cos = math.cos
    for cents in (-detune_c, 0.0, detune_c):
        inc = f * 2 ** (cents / 1200.0) * _TAB / SR
        ph = rng.uniform(0, _TAB)
        g = 1.0
        for t in range(n):
            i = int(ph)
            y = tab[i] + (ph - i) * (tab[i + 1] - tab[i])
            e = 0.5 - 0.5 * cos(math.pi * t / att) if t < att else 1.0
            if t >= n_on:
                g *= k_rel
                e *= g
            out[t] += y * e * 0.3333
            ph += inc
            if ph >= _TAB:
                ph -= _TAB
    return out


def wind(f, dur, vel, seed, breath=0.08, chiff=0.25, vib=0.004, vib_hz=5.2,
         h2=0.12, h3=0.04, attack=0.05):
    """Flute, pan flute or whistle: a near-sine with breath and late vibrato."""
    rng = random.Random(seed)
    n_on = int(dur * SR)
    n = n_on + int(0.15 * SR)
    out = zeros(n)
    att = max(1.0, attack * SR)
    k_rel = math.exp(-1.0 / (0.05 * SR))
    k_ch = math.exp(-1.0 / (0.025 * SR))
    wv = TAU * vib_hz / SR
    ph, lp, g, ch = 0.0, 0.0, 1.0, 1.0
    sin = math.sin
    for t in range(n):
        depth = vib * min(1.0, max(0.0, (t / SR - 0.18) / 0.3))
        ph += TAU * f * (1.0 + depth * sin(wv * t)) / SR
        y = sin(ph) + h2 * sin(2 * ph) + h3 * sin(3 * ph)
        lp += 0.25 * (rng.uniform(-1, 1) - lp)
        e = t / att if t < att else 1.0
        if t >= n_on:
            g *= k_rel
            e *= g
        out[t] = (y + (breath + chiff * ch) * lp * 2.0) * e
        ch *= k_ch
    return out


# (ratio to the fundamental, amplitude, decay seconds at A4)
KALIMBA = ((1.0, 1.0, 1.1), (2.0, 0.06, 0.4), (5.9, 0.22, 0.05))


def mallet(f, dur, vel, seed, partials=KALIMBA, noise=0.1):
    """Struck or plucked tines — here only the kalimba, whose VCSL recordings are
    tuned to their own (non-equal) scale and so cannot play these chords."""
    rng = random.Random(seed)
    scale = (440.0 / f) ** 0.3
    longest = max(p[2] for p in partials) * scale
    n = int(min(dur + longest * 5.0, 6.0) * SR)
    out = zeros(n)
    sin = math.sin
    for ratio, amp, tau in partials:
        fk = f * ratio
        if fk > NYQ_SAFE:
            continue
        w = TAU * fk / SR
        k = math.exp(-1.0 / (tau * scale * SR))
        e = amp
        for t in range(n):
            out[t] += e * sin(w * t)
            e *= k
            if e < 1e-5:
                break
    m = int(0.004 * SR)
    lp = 0.0
    for t in range(m):
        lp += 0.3 * (rng.uniform(-1, 1) - lp)
        out[t] += noise * lp * (1 - t / m)
    return out


def kick(f, dur, vel, seed, f_start=120.0, f_end=48.0, sweep=0.035, decay=0.24,
         click=0.04, drive=0.8, length=0.6):
    """A soft electronic kick for the lo-fi kit: VCSL's bass drum is a concert
    drum, too long and too wide to sit under a city-pop groove."""
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


def vinyl(f, dur, vel, seed):
    """Record crackle and hiss, exactly `dur` long so a loop wraps cleanly."""
    rng = random.Random(seed)
    n = int(round(dur * SR))
    out = zeros(n)
    a_hiss = _lp_coef(5000.0)
    lp = 0.0
    for t in range(n):
        lp += a_hiss * (rng.uniform(-1, 1) - lp)
        out[t] = 0.02 * lp
    t = 0
    while True:
        t += int(rng.expovariate(7.0) * SR) + 1
        if t >= n - 64:
            break
        amp = rng.uniform(0.04, 0.3) * (1 if rng.random() < 0.5 else -1)
        k = math.exp(-1.0 / (rng.uniform(0.0002, 0.0006) * SR))
        e = amp
        for j in range(64):
            out[t + j] += e * (1 if j % 2 == 0 else -0.6)
            e *= k
    return out


# ---------------------------------------------------------------- recorded instruments (VCSL, CC0)

VCSL_URL = 'https://github.com/sgossner/VCSL'
VCSL_COMMIT = 'c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e'
_S = 'Idiophones/Struck Idiophones/'
_M = 'Membranophones/Struck Membranophones/'
_Z = 'Chordophones/Zithers/'
# What `fetch` checks out — about 0.45 GB of the library, not the whole of it.
VCSL_PATHS = (
    'LICENSE',
    _Z + 'Upright Piano, Yamaha/Sustains/*_vl2_rr1.wav',
    _Z + 'Upright Piano, Yamaha/Sustains/*_vl3_rr1.wav',
    _Z + 'Grand Piano, Kawai/Sustains/*_v2_rr1_*',
    _Z + 'Grand Piano, Kawai/Sustains/*_v3_rr1_*',
    _Z + 'Dan Tranh/Normal/*',
    _Z + 'Dan Tranh/Gliss/Gliss_Up_Med_mf_1.wav',
    _S + 'Vibraphone/Soft Mallets/*',
    _S + 'Marimba/*',
    _S + 'Glockenspiel/*',
    _S + 'Mark Trees/Legacy/*',
    _S + 'Suspended Cymbal 1/susCymb1_hit_*',
    _S + 'Suspended Cymbal 1/susCymb1_cresc_2s.wav',
    _S + 'Hi-Hat Cymbal/*',
    _S + 'Cajon/*',
    _S + 'Claps/*',
    _S + 'Shaker, Small/*',
    _S + 'Tambourine 1/*',
    _M + 'Snare Drum, Modern 2/*',
    _M + 'Conga/*',
    _M + 'Bongos/*',
    _M + 'Bass Drum 1/*',
    _M + 'Tom 1/Mallet/*',
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


def roll(f, dur, vel, seed, bank=None):
    """A recorded roll, held for `dur` and pushed into a crescendo."""
    L, R = hit(f, dur, vel, seed, bank=bank)
    n = min(len(L), int(dur * SR))
    outs = []
    for ch in (L, R):
        o = array('f', ch[:n])
        for i in range(n):
            o[i] *= 0.15 + 0.85 * (i / n) ** 1.5
        outs.append(o)
    _fade_tail(outs, int(0.01 * SR))
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
    'dantranh': Bank(_Z + 'Dan Tranh/Normal', r'^' + _N + r'_(?P<layer>mf|f|ff)_1',
                     ('mf', 'f', 'ff'), pitched=True, autotune=True, max_s=4.0),
    'dantranh_gliss': Bank(_Z + 'Dan Tranh/Gliss', r'Gliss_Up_Med_mf', max_s=4.0),
    'chimes_up': Bank(_S + 'Mark Trees/Legacy', r'windchimes_fastAsc1', max_s=5.0),
    'chimes_down': Bank(_S + 'Mark Trees/Legacy', r'windchimes_slowDesc1', max_s=7.0),
    'cymbal': Bank(_S + 'Suspended Cymbal 1', r'susCymb1_hit_(?P<layer>pp|mp|fff|f)\d\.wav',
                   ('pp', 'mp', 'f', 'fff'), max_s=5.0),
    'cymbal_swell': Bank(_S + 'Suspended Cymbal 1', r'susCymb1_cresc_2s', max_s=5.0),
    'hh': Bank(_S + 'Hi-Hat Cymbal', r'HiHat_HitC_v(?P<layer>\d)_rr', ('1', '2', '3', '4'), max_s=0.6),
    'hh_open': Bank(_S + 'Hi-Hat Cymbal', r'HiHat_HitO_rr', max_s=1.2),
    'xstick': Bank(_M + 'Snare Drum, Modern 2', r'Xstick_v2_rr', max_s=0.6),
    'snare': Bank(_M + 'Snare Drum, Modern 2', r'HitSN_v(?P<layer>\d)_rr', ('2', '3', '4', '5'),
                  max_s=1.2),
    'cajon_bass': Bank(_S + 'Cajon', r'hit2_(?P<layer>pp|mp|f)_rr', ('pp', 'mp', 'f'), max_s=0.8),
    'claps': Bank(_S + 'Claps', r'^Clap_rr', max_s=0.8),
    'shaker_dn': Bank(_S + 'Shaker, Small', r'ShakerHighFaster_Down_rr', max_s=0.4),
    'shaker_up': Bank(_S + 'Shaker, Small', r'ShakerHighFaster_Up_rr', max_s=0.4),
    'tamb': Bank(_S + 'Tambourine 1', r'Tamb1_Hit_v(?P<layer>\d)_rr', ('1', '2'), max_s=0.8),
    'tamb_roll': Bank(_S + 'Tambourine 1', r'Tamb1_Roll_v(?P<layer>\d)_rr', ('1', '2', '3'), max_s=4.0),
    'conga': Bank(_M + 'Conga', r'^Conga_HitN_v(?P<layer>\d)_rr', ('1', '2', '3'), max_s=0.8),
    'conga_mute': Bank(_M + 'Conga', r'^Conga_HitFM_v(?P<layer>\d)_rr', ('1', '2'), max_s=0.5),
    'quinto': Bank(_M + 'Conga', r'^Quinto_HitN_v(?P<layer>\d)_rr', ('1', '2', '3'), max_s=0.8),
    'tumba': Bank(_M + 'Conga', r'^Tumba_HitN_v(?P<layer>\d)_rr', ('1', '2', '3', '4'), max_s=0.8),
    'bongo_roll': Bank(_M + 'Bongos', r'BongoH_Roll_v(?P<layer>\d)_rr', ('2', '3'), max_s=4.0),
    'bass_drum': Bank(_M + 'Bass Drum 1', r'BDrumNew_hit_v(?P<layer>\d)_rr', ('2', '3', '5', '7'),
                      max_s=2.5),
    'tom': Bank(_M + 'Tom 1/Mallet', r'TomH_HitM_v(?P<layer>\d)_rr', ('2', '3', '4'), max_s=1.5),
    'tom_roll': Bank(_M + 'Tom 1/Mallet', r'TomH_RollM_v(?P<layer>\d)_rr', ('1', '2'), max_s=4.0),
}


# name: (render function, its options, mix gain, seed variants, is a drum)
INST = {
    'ep': (ep, {}, 0.30, 1, False),
    'nylon': (pluck, dict(bright=0.38, t60=2.2, pick=0.16), 1.20, 3, False),
    'steel': (pluck, dict(bright=0.75, t60=3.5, pick=0.12), 1.30, 3, False),
    'bass': (bass, {}, 0.46, 1, False),
    'sub': (bass, dict(bright=0.12, attack=0.03), 0.50, 1, False),
    'pad': (pad, {}, 0.11, 1, False),
    'shimmer': (pad, dict(attack=1.6, release=2.0, nh_cap=4, detune_c=11.0), 0.07, 1, False),
    'flute': (wind, {}, 0.23, 1, False),
    'panflute': (wind, dict(breath=0.2, chiff=0.6, vib=0.003, h2=0.06, h3=0.08), 0.23, 1, False),
    'whistle': (wind, dict(breath=0.04, chiff=0.1, vib=0.007, vib_hz=6.0, h2=0.02, h3=0.0,
                           attack=0.03), 0.26, 1, False),
    'kalimba': (mallet, {}, 0.26, 1, False),
    'kick': (kick, {}, 0.70, 4, True),
    'vinyl': (vinyl, {}, 0.70, 1, False),
    'upright': (sampled, dict(bank='upright', release=0.35), 0.70, 1, False),
    'grand': (sampled, dict(bank='grand', release=0.4), 1.0, 1, False),
    'vibes': (sampled, dict(bank='vibes', release=0.5), 0.35, 1, False),
    'marimba': (sampled, dict(bank='marimba', release=0.2, ring=1.2), 0.37, 1, False),
    'glock': (sampled, dict(bank='glock', release=0.4, ring=1.6), 1.0, 1, False),
    'dantranh': (sampled, dict(bank='dantranh', release=0.5, ring=2.0), 1.20, 1, False),
    'dantranh_gliss': (hit, dict(bank='dantranh_gliss', semis=-2.0), 1.50, 1, False),
    'chimes_up': (hit, dict(bank='chimes_up'), 1.40, 1, False),
    'chimes_down': (hit, dict(bank='chimes_down'), 1.40, 1, False),
    'cymbal': (hit, dict(bank='cymbal'), 1.25, 1, True),
    'cymbal_swell': (swell, dict(bank='cymbal_swell'), 1.0, 1, True),
    'hh': (hit, dict(bank='hh'), 1.0, 2, True),
    'hh_lofi': (hit, dict(bank='hh', lp_hz=7000.0), 1.40, 2, True),
    'hh_open': (hit, dict(bank='hh_open'), 1.20, 2, True),
    'xstick': (hit, dict(bank='xstick'), 2.00, 2, True),
    'snare': (hit, dict(bank='snare'), 2.00, 2, True),
    'cajon_bass': (hit, dict(bank='cajon_bass'), 2.00, 2, True),
    'claps': (hit, dict(bank='claps'), 2.80, 6, True),
    'shaker_dn': (hit, dict(bank='shaker_dn'), 1.40, 2, True),
    'shaker_up': (hit, dict(bank='shaker_up'), 1.40, 2, True),
    'tamb': (hit, dict(bank='tamb'), 1.0, 1, True),
    'tamb_roll': (roll, dict(bank='tamb_roll'), 1.35, 1, True),
    'conga': (hit, dict(bank='conga'), 1.0, 2, True),
    'conga_mute': (hit, dict(bank='conga_mute'), 1.0, 2, True),
    'quinto': (hit, dict(bank='quinto'), 1.0, 2, True),
    'tumba': (hit, dict(bank='tumba'), 1.0, 2, True),
    'bongo_roll': (roll, dict(bank='bongo_roll'), 1.35, 1, True),
    'bass_drum': (hit, dict(bank='bass_drum'), 1.60, 2, True),
    'tom': (hit, dict(bank='tom'), 2.00, 2, True),
    'tom_roll': (roll, dict(bank='tom_roll'), 1.35, 1, True),
}


# ---------------------------------------------------------------- composition

class Chord:
    def __init__(self, voicing, bass_note, gtr=None):
        self.v = chord(voicing)
        self.bass = midi(bass_note)
        self.gtr = chord(gtr) if gtr else None


def segments(prog, bars):
    """(start beat, length in beats, Chord) for every chord over `bars` bars."""
    out = []
    for b in range(bars):
        for s, d, c in prog[b % len(prog)]:
            out.append((b * 4 + s, d, c))
    return out


def theme(melody, transpose=0):
    """A melody's skeleton: the notes that fall on a beat, each held to the next.
    The stop loops play it, so the film keeps one tune across its turns."""
    kept = [(b, midi(nm) + transpose) for b, d, nm in melody if abs(b - round(b)) < 1e-9]
    out = []
    for i, (b, p) in enumerate(kept):
        nxt = kept[i + 1][0] if i + 1 < len(kept) else math.floor(b / 4) * 4 + 4
        out.append((b, min(2.0, nxt - b), p))
    return out


class Section:
    """One loop or one-shot: a list of notes on the style's beat grid."""

    def __init__(self, style, name, bars, loop, tail_s, anchor_beats, lp_hz):
        self.style, self.name, self.bars = style, name, bars
        self.loop, self.tail_s, self.anchor_beats, self.lp_hz = loop, tail_s, anchor_beats, lp_hz
        self.beat_s = 60.0 / style.bpm
        self.rng = random.Random(f'{style.name}/{name}')
        self.notes = []

    def _swing(self, beat):
        unit, amt = self.style.swing
        if not amt:
            return beat
        fr = beat - math.floor(beat + 1e-9)
        if unit == 8 and abs(fr - 0.5) < 0.07:
            return beat + amt
        if unit == 16 and (abs(fr - 0.25) < 0.05 or abs(fr - 0.75) < 0.05):
            return beat + amt
        return beat

    def n(self, beat, inst, pitch=None, dur=0.5, vel=0.8, pan=0.0, send=0.15, raw=False):
        if not raw:
            beat = self._swing(beat)
        is_drum = INST[inst][4]
        jitter = self.rng.gauss(0.0, 0.002 if is_drum else 0.004) / self.beat_s
        vel = vel * (1.0 + self.rng.uniform(-0.06, 0.06))
        self.notes.append((beat + jitter, inst, pitch, dur, vel, pan, send))

    def strum(self, beat, inst, pitches, dur, vel, up=False, spread_s=0.012, pan=0.0, send=0.15):
        base = self._swing(beat)
        order = pitches[::-1] if up else pitches
        step = spread_s / self.beat_s
        mid = (len(order) - 1) / 2.0
        for i, p in enumerate(order):
            self.n(base + i * step, inst, p, max(0.05, dur - i * step), vel * (1.0 - 0.05 * i),
                   pan + 0.05 * (i - mid), send, raw=True)

    def gliss(self, beat, inst, pitches, step_s, vel, pan=0.0, send=0.3, dur=1.0):
        base = self._swing(beat)
        for i, p in enumerate(pitches):
            self.n(base + i * step_s / self.beat_s, inst, p, dur, vel, pan + 0.1 * (i % 3 - 1),
                   send, raw=True)


class Style:
    def __init__(self, name, title, bpm, swing, room, damp, wet, countries):
        assert (SR * 60) % bpm == 0, f'{bpm} BPM is not a whole number of samples per beat'
        self.name, self.title, self.bpm = name, title, bpm
        self.swing, self.room, self.damp, self.wet = swing, room, damp, wet
        self.countries = countries
        self.sections = {}

    def sec(self, name, bars, loop=True, tail_s=0.0, anchor_beats=0.0, lp_hz=None):
        s = Section(self, name, bars, loop, tail_s, anchor_beats, lp_hz)
        self.sections[name] = s
        return s


def _crackle(s):
    s.n(0, 'vinyl', None, s.bars * 4, 1.0, 0.0, 0.0, raw=True)


def _riser(s, roll_inst, roll_vel):
    """The last bar before a turn: a cymbal swells into the beat over a roll."""
    s.n(0, 'cymbal_swell', None, 4, 0.6, 0.0, 0.25, raw=True)
    if roll_inst:
        s.n(2, roll_inst, None, 2, roll_vel, 0.0, 0.2, raw=True)


def east_asia():
    """JP · TW · KR — light lo-fi, city pop. 90 BPM, swung 8ths.

    The 'Marunouchi' city-pop turn, IVmaj7–III7–vim7–vm7 I7, in F: Bbmaj9 | A9 |
    Dm9 | Cm9 F9 — rootless voicings on the electric piano. The guitar of the
    first draft read as unnatural (Chiu); an upright piano and a vibraphone take
    its place, both recorded.
    """
    st = Style('east-asia', 'Neon Rain', 90, (8, 0.06), room=0.55, damp=0.5, wet=0.8,
               countries=('JP', 'TW', 'KR'))
    P = [
        [(0, 4, Chord('D4 F4 A4 C5', 'Bb1'))],
        [(0, 4, Chord('C#4 G4 B4 E5', 'A1'))],
        [(0, 4, Chord('F4 A4 C5 E5', 'D2'))],
        [(0, 2, Chord('Eb4 G4 Bb4 D5', 'C2')), (2, 2, Chord('A3 Eb4 G4 C5', 'F1'))],
    ]
    melody = [  # (beat, beats, note) — F major pentatonic plus chord colour
        (0.5, 0.5, 'D5'), (1.0, 0.5, 'F5'), (1.5, 1.5, 'A5'), (3.0, 0.5, 'G5'), (3.5, 0.5, 'F5'),
        (4.0, 1.0, 'E5'), (5.0, 0.5, 'D5'), (5.5, 1.5, 'C#5'), (7.0, 0.5, 'A4'), (7.5, 0.5, 'C5'),
        (8.0, 1.5, 'D5'), (9.5, 0.5, 'C5'), (10.0, 1.0, 'A4'), (11.0, 0.5, 'C5'), (11.5, 0.5, 'D5'),
        (12.0, 1.0, 'Eb5'), (13.0, 0.5, 'D5'), (13.5, 0.5, 'C5'), (14.0, 1.5, 'A4'), (15.5, 0.5, 'C5'),
        (16.5, 0.5, 'F5'), (17.0, 0.5, 'G5'), (17.5, 1.5, 'A5'), (19.0, 0.5, 'C6'), (19.5, 0.5, 'A5'),
        (20.0, 1.5, 'G5'), (21.5, 0.5, 'F5'), (22.0, 1.5, 'E5'), (23.5, 0.5, 'C#5'),
        (24.0, 1.0, 'D5'), (25.0, 0.5, 'E5'), (25.5, 0.5, 'F5'), (26.0, 1.0, 'E5'), (27.0, 1.0, 'C5'),
        (28.0, 1.0, 'D5'), (29.0, 1.0, 'Bb4'), (30.0, 2.0, 'A4'),
    ]

    def comp(s, vel):
        for start, dur, c in segments(P, s.bars):
            hits = [(0, 1.4, 1.0), (2.5, 1.3, 0.75)] if dur == 4 else [(0, 1.3, 0.9)]
            for o, d, v in hits:
                s.strum(start + o, 'ep', c.v, d, vel * v, spread_s=0.008, pan=-0.15, send=0.22)

    def bassline(s, vel):
        for start, dur, c in segments(P, s.bars):
            pat = [(0, 0.9, 0, 0.95), (1.5, 0.4, 0, 0.6), (2.5, 0.75, 7, 0.75), (3.5, 0.4, 12, 0.55)] \
                if dur == 4 else [(0, 0.9, 0, 0.9), (1.5, 0.4, 7, 0.6)]
            for o, d, iv, v in pat:
                s.n(start + o, 'bass', c.bass + iv, d, vel * v, 0.0, 0.0)

    def drums(s, vel):
        for b in range(s.bars):
            o, last = b * 4, b % 4 == 3
            for k, v in ((0, 0.9), (1.5, 0.45), (2.5, 0.75)) + (((3.5, 0.4),) if last else ()):
                s.n(o + k, 'kick', None, 0.5, vel * v, 0.0, 0.05)
            for k in (1, 3):
                s.n(o + k, 'xstick', None, 0.5, vel * 0.7, 0.05, 0.18)
            for i, v in enumerate((0.45, 0.22, 0.35, 0.22, 0.45, 0.22, 0.35, 0.25)):
                if last and i == 7:
                    s.n(o + 3.5, 'hh_open', None, 0.5, vel * 0.3, 0.2, 0.12)
                else:
                    s.n(o + i * 0.5, 'hh_lofi', None, 0.25, vel * v, 0.2, 0.1)

    def piano_chord(s, start, dur, c, vel, roll_s=0.03):
        s.strum(start, 'upright', [c.bass + 12, c.bass + 19] + c.v, dur, vel, spread_s=roll_s,
                send=0.3)

    s = st.sec('intro', 4, lp_hz=1600.0)
    for start, dur, c in segments(P, 4):
        piano_chord(s, start, dur - 0.1, c, 0.6)
    _crackle(s)

    s = st.sec('travel_a', 4)
    comp(s, 0.7)
    bassline(s, 0.85)
    drums(s, 0.85)
    _crackle(s)

    s = st.sec('travel_b', 8)
    comp(s, 0.6)
    bassline(s, 0.85)
    drums(s, 0.9)
    for b, d, nm in melody:
        s.n(b, 'flute', midi(nm), d * 0.95, 0.8, 0.05, 0.3)
    for start, dur, c in segments(P, 8):
        s.strum(start, 'vibes', c.v[-2:], min(dur, 2.0), 0.4, spread_s=0.02, pan=0.35, send=0.3)
    _crackle(s)

    s = st.sec('stop', 8)
    for start, dur, c in segments(P, 8):
        s.n(start, 'upright', c.bass + 12, dur, 0.32, -0.1, 0.3)
        for i in range(int(dur * 2) - 1):
            s.n(start + 0.5 + i * 0.5, 'upright', c.v[(0, 1, 2, 3, 2, 1, 2)[i % 7]], 1.0, 0.28, -0.1, 0.3)
        s.n(start, 'bass', c.bass, dur - 0.3, 0.45, 0.0, 0.0)
    for b, d, p in theme(melody, -12):
        s.n(b, 'vibes', p, d, 0.65, 0.25, 0.3)
    for b in range(8):
        for i in range(8):
            s.n(b * 4 + i * 0.5, 'shaker_dn' if i % 2 == 0 else 'shaker_up', None, 0.25,
                0.3 if i % 2 else 0.2, -0.25, 0.1)
    _crackle(s)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    _riser(s, None, 0)
    for i in range(8):
        s.n(2 + i * 0.25, 'hh', None, 0.25, 0.15 + 0.07 * i, 0.2, 0.1, raw=True)

    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'cymbal', None, 4, 0.55, 0.1, 0.3, raw=True)
    s.n(0, 'kick', None, 1, 1.0, 0.0, 0.05, raw=True)
    s.n(0, 'snare', None, 1, 0.45, 0.0, 0.25, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=3.5)
    s.n(0, 'chimes_up', None, 4, 0.6, 0.0, 0.3, raw=True)

    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    s.strum(0, 'upright', chord('F2 C3 A3 C4 E4 G4'), 7, 0.75, spread_s=0.05, send=0.35)
    s.strum(0.25, 'vibes', chord('A4 C5 E5'), 6, 0.7, spread_s=0.06, pan=0.3, send=0.35)
    s.n(0, 'bass', midi('F1'), 5, 0.7, 0.0, 0.0, raw=True)
    s.n(0.5, 'chimes_down', None, 4, 0.45, 0.0, 0.3, raw=True)
    return st


def nordic():
    """IS · NO — ambient, grand piano, post-rock. 80 BPM, straight, a big room.

    I–V–vi–IV in D, opened up: Dadd9 | A/C# | Bm7 | Gmaj7(#11). The first draft's
    tune was a tremolo guitar holding long notes, and read as monotonous (Chiu);
    this one moves — eighth-note pickups, leaps, a climb to D6 in bar 5.
    """
    st = Style('nordic', 'Northern Light', 80, (8, 0.0), room=0.88, damp=0.3, wet=1.15,
               countries=('IS', 'NO'))
    P = [
        [(0, 4, Chord('A3 D4 E4 F#4', 'D2'))],
        [(0, 4, Chord('A3 C#4 E4 B4', 'C#2'))],
        [(0, 4, Chord('F#3 B3 D4 A4', 'B1'))],
        [(0, 4, Chord('B3 D4 F#4 C#5', 'G1'))],
    ]
    melody = [
        (0, 1, 'F#5'), (1, 0.5, 'E5'), (1.5, 0.5, 'D5'), (2, 1.5, 'A5'), (3.5, 0.5, 'F#5'),
        (4, 1.5, 'E5'), (5.5, 0.5, 'C#5'), (6, 0.5, 'E5'), (6.5, 0.5, 'F#5'), (7, 1, 'A5'),
        (8, 1.5, 'B5'), (9.5, 0.5, 'A5'), (10, 1, 'F#5'), (11, 0.5, 'D5'), (11.5, 0.5, 'E5'),
        (12, 2, 'F#5'), (14, 0.5, 'E5'), (14.5, 0.5, 'D5'), (15, 0.5, 'C#5'), (15.5, 0.5, 'A4'),
        (16, 0.5, 'D5'), (16.5, 0.5, 'F#5'), (17, 1, 'A5'), (18, 1.5, 'D6'), (19.5, 0.5, 'C#6'),
        (20, 1, 'B5'), (21, 1, 'A5'), (22, 1.5, 'E5'), (23.5, 0.5, 'F#5'),
        (24, 1, 'D6'), (25, 0.5, 'B5'), (25.5, 0.5, 'A5'), (26, 1, 'F#5'), (27, 1, 'A5'),
        (28, 1.5, 'F#5'), (29.5, 0.5, 'E5'), (30, 2, 'D5'),
    ]

    def pads(s, vel, shimmer):
        for start, dur, c in segments(P, s.bars):
            for i, p in enumerate(c.v):
                s.n(start, 'pad', p, dur, vel, -0.45 + 0.3 * i, 0.45, raw=True)
            if shimmer:
                for i, p in enumerate(c.v[-2:]):
                    s.n(start, 'shimmer', p + 12, dur, shimmer, -0.6 + 1.2 * i, 0.7, raw=True)

    def arps(s, vel):
        for start, dur, c in segments(P, s.bars):
            for i, p in enumerate([c.bass + 12] + c.v + c.v[2::-1]):
                s.n(start + i * 0.5, 'grand', p, 1.5, vel * (1.0 if i in (0, 4) else 0.75), -0.15, 0.4)

    def low(s, vel):
        for start, dur, c in segments(P, s.bars):
            s.n(start, 'sub', c.bass, dur - 0.1, vel, 0.0, 0.0)

    s = st.sec('intro', 4)
    pads(s, 0.6, 0.55)
    low(s, 0.3)
    for start, dur, c in segments(P, 4):
        s.n(start, 'grand', c.v[3] + 12, 2.0, 0.45, 0.2, 0.55)
        s.n(start + 2, 'grand', c.v[2] + 12, 2.0, 0.4, -0.2, 0.55)

    s = st.sec('travel_a', 4)
    pads(s, 0.4, 0.0)
    arps(s, 0.55)
    low(s, 0.55)
    for b in range(4):
        s.n(b * 4, 'bass_drum', None, 1, 0.45, 0.0, 0.25)
        s.n(b * 4 + 2.5, 'bass_drum', None, 1, 0.3, 0.0, 0.25)
        for i in range(8):
            s.n(b * 4 + i * 0.5, 'shaker_dn' if i % 2 == 0 else 'shaker_up', None, 0.25,
                0.3 if i % 2 else 0.2, -0.3, 0.2)

    s = st.sec('travel_b', 8)
    pads(s, 0.4, 0.3)
    arps(s, 0.42)
    low(s, 0.55)
    for beat, d, nm in melody:
        s.n(beat, 'grand', midi(nm), d * 1.1, 0.7, 0.1, 0.4)
        if beat >= 16:
            s.n(beat, 'glock', midi(nm) + 12, d, 0.25, -0.3, 0.45)
    for b in range(8):
        o = b * 4
        s.n(o, 'bass_drum', None, 1, 0.6, 0.0, 0.3)
        s.n(o + 2.5, 'bass_drum', None, 1, 0.35, 0.0, 0.3)
        s.n(o + 2, 'snare', None, 0.5, 0.5, 0.0, 0.45)
        if b in (3, 7):
            for i, k in enumerate((2, 2.5, 3, 3.5)):
                s.n(o + k, 'tom', None, 0.5, 0.35 + 0.08 * i, 0.15, 0.35)
        if b in (0, 4):
            s.n(o, 'cymbal', None, 4, 0.3, -0.3, 0.45)
    s.n(12, 'cymbal_swell', None, 4, 0.45, 0.2, 0.4, raw=True)
    s.n(28, 'cymbal_swell', None, 4, 0.45, 0.2, 0.4, raw=True)

    s = st.sec('stop', 8)
    pads(s, 0.4, 0.45)
    for start, dur, c in segments(P, 8):
        s.n(start, 'grand', c.bass + 12, 2.0, 0.35, -0.25, 0.45)
        s.n(start + 2, 'grand', c.bass + 19, 2.0, 0.3, -0.25, 0.45)
        s.n(start, 'sub', c.bass, dur - 0.1, 0.35, 0.0, 0.0)
    for b, d, p in theme(melody, -12):
        s.n(b, 'grand', p, d, 0.5, 0.15, 0.5)

    s = st.sec('riser', 1, loop=False, tail_s=0.8, anchor_beats=4)
    _riser(s, 'tom_roll', 0.6)

    s = st.sec('hit_big', 1, loop=False, tail_s=4.0)
    s.n(0, 'cymbal', None, 4, 0.75, -0.2, 0.5, raw=True)
    s.n(0, 'bass_drum', None, 2, 1.0, 0.0, 0.3, raw=True)
    s.n(0, 'tom', None, 1, 0.6, 0.1, 0.4, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=3.5)
    s.n(0, 'chimes_up', None, 4, 0.55, 0.0, 0.5, raw=True)

    s = st.sec('outro', 2, loop=False, tail_s=5.0)
    s.strum(0, 'grand', chord('D2 A2 D3 F#3 A3 E4 F#4 A4'), 8, 0.6, spread_s=0.05, send=0.5)
    for i, p in enumerate(chord('A3 D4 E4 F#4')):
        s.n(0, 'pad', p, 6, 0.4, -0.45 + 0.3 * i, 0.5, raw=True)
    s.n(0, 'shimmer', midi('F#5'), 6, 0.5, -0.5, 0.7, raw=True)
    s.n(0, 'shimmer', midi('A5'), 6, 0.5, 0.5, 0.7, raw=True)
    s.n(1, 'glock', midi('D6'), 2, 0.35, 0.3, 0.6, raw=True)
    s.n(0.5, 'chimes_down', None, 4, 0.4, 0.0, 0.5, raw=True)
    s.n(0, 'cymbal', None, 4, 0.3, -0.2, 0.5, raw=True)
    return st


def southeast_asia():
    """VN · TH — warm acoustic, light tropical. 100 BPM, a touch of 16th swing.

    I–vi–IV–V in A: A(add9) | F#m7 | Dmaj7 | Esus4 E. The Đàn Tranh, Vietnam's
    zither, is tuned pentatonic; moved down a tone its scale is A major
    pentatonic, which sits on every chord here.
    """
    st = Style('southeast-asia', 'Coconut Road', 100, (16, 0.035), room=0.7, damp=0.5, wet=0.8,
               countries=('VN', 'TH'))
    P = [
        [(0, 4, Chord('E4 A4 B4 C#5', 'A1', 'A2 E3 A3 C#4 E4'))],
        [(0, 4, Chord('E4 F#4 A4 C#5', 'F#1', 'F#2 C#3 E3 A3 C#4'))],
        [(0, 4, Chord('D4 F#4 A4 C#5', 'D2', 'D3 A3 C#4 F#4'))],
        [(0, 2, Chord('E4 A4 B4', 'E2', 'E2 B2 E3 A3 B3 E4')),
         (2, 2, Chord('E4 G#4 B4', 'E2', 'E2 B2 E3 G#3 B3 E4'))],
    ]
    melody = [(0, 0.5, 'C#5'), (0.5, 0.5, 'E5'), (1, 1, 'F#5'), (2, 0.5, 'E5'), (2.5, 1.5, 'C#5'),
              (4.5, 0.5, 'A4'), (5, 0.5, 'C#5'), (5.5, 0.5, 'E5'), (6, 2, 'F#5'), (8, 0.5, 'A5'),
              (8.5, 0.5, 'F#5'), (9, 1, 'E5'), (10, 0.5, 'C#5'), (10.5, 1.5, 'E5'), (12, 1, 'B4'),
              (13, 1, 'C#5'), (14, 2, 'B4'), (16, 0.5, 'E5'), (16.5, 0.5, 'F#5'), (17, 1, 'A5'),
              (18, 0.5, 'F#5'), (18.5, 1.5, 'E5'), (20.5, 0.5, 'C#5'), (21, 0.5, 'E5'),
              (21.5, 0.5, 'F#5'), (22, 2, 'A5'), (24, 1, 'F#5'), (25, 0.5, 'E5'), (25.5, 0.5, 'C#5'),
              (26, 2, 'E5'), (28, 1.5, 'B4'), (29.5, 0.5, 'C#5'), (30, 2, 'E5')]

    def chord_at(beat):
        for start, dur, c in segments(P, 4):
            if start <= beat % 16 < start + dur:
                return c
        raise AssertionError(beat)

    def strums(s, vel):
        pat = [(0, 'D', 0.75), (1, 'D', 0.55), (1.5, 'U', 0.4), (2.5, 'U', 0.4),
               (3, 'D', 0.55), (3.5, 'U', 0.42)]
        for b in range(s.bars):
            for i, (o, d, v) in enumerate(pat):
                beat = b * 4 + o
                nxt = pat[i + 1][0] if i + 1 < len(pat) else 4
                g = chord_at(beat).gtr
                s.strum(beat, 'steel', g if d == 'D' else g[-4:], (nxt - o) * 0.95, vel * v,
                        up=(d == 'U'), pan=0.3, send=0.18)

    def fingerpick(s, vel):
        for start, dur, c in segments(P, s.bars):
            g = c.gtr
            for i in range(int(dur * 2)):
                j = min((0, 2, 3, 4, 1, 3, 4, 3)[i % 8], len(g) - 1)
                s.n(start + i * 0.5, 'nylon', g[j], 1.2, vel * (0.9 if i % 2 == 0 else 0.7), 0.3, 0.22)

    def kalimba_line(s, vel):
        for start, dur, c in segments(P, s.bars):
            steps = ((0, 3), (0.75, 1), (1.5, 2), (2.5, 3), (3, 0)) if dur == 4 \
                else ((0, 2), (0.75, 1), (1.5, 0))
            for o, j in steps:
                s.n(start + o, 'kalimba', c.v[min(j, len(c.v) - 1)], 0.5, vel, -0.3, 0.3)

    def bassline(s, vel):
        for start, dur, c in segments(P, s.bars):
            pat = [(0, 0.9, 0, 0.9), (1.5, 0.4, 0, 0.6), (2.5, 0.4, 7, 0.55), (3, 0.9, 0, 0.75)] \
                if dur == 4 else [(0, 0.9, 0, 0.9), (1.5, 0.4, 7, 0.55)]
            for o, d, iv, v in pat:
                s.n(start + o, 'bass', c.bass + iv, d, vel * v, 0.0, 0.0)

    def perc(s, vel):
        for b in range(s.bars):
            o = b * 4
            for k in (0, 2):
                s.n(o + k, 'cajon_bass', None, 0.5, vel * 0.65, 0.0, 0.12)
            for k in (1, 3):
                s.n(o + k, 'claps', None, 0.5, vel * 0.45, 0.0, 0.2)
            for i in range(8):
                s.n(o + i * 0.5, 'shaker_dn' if i % 2 == 0 else 'shaker_up', None, 0.25,
                    vel * (0.4 if i % 2 else 0.28), -0.25, 0.1)

    def marimba_offbeats(s, vel):
        for b in range(s.bars):
            for o in (0.5, 1.5, 2.5, 3.5):
                for p in chord_at(b * 4 + o).v[-2:]:
                    s.n(b * 4 + o, 'marimba', p, 0.3, vel, -0.3, 0.2)

    s = st.sec('intro', 4)
    s.n(0, 'dantranh_gliss', None, 4, 0.55, 0.1, 0.35, raw=True)
    kalimba_line(s, 0.45)
    for start, dur, c in segments(P, 4):
        for i, p in enumerate(c.v):
            s.n(start, 'pad', p, dur, 0.3, -0.4 + 0.25 * i, 0.4, raw=True)

    s = st.sec('travel_a', 4)
    strums(s, 0.75)
    bassline(s, 0.85)
    perc(s, 0.85)
    marimba_offbeats(s, 0.35)

    s = st.sec('travel_b', 8)
    strums(s, 0.7)
    bassline(s, 0.85)
    perc(s, 0.9)
    marimba_offbeats(s, 0.28)
    for b in range(8):
        for o, inst, v in ((0.75, 'tumba', 0.5), (1.5, 'quinto', 0.55), (2.5, 'quinto', 0.5),
                           (2.75, 'tumba', 0.45), (3.5, 'conga_mute', 0.6)):
            s.n(b * 4 + o, inst, None, 0.25, v, 0.25 if inst == 'quinto' else -0.1, 0.15)
    for beat, d, nm in melody:
        s.n(beat, 'panflute', midi(nm), d * 0.95, 0.8, 0.05, 0.3)

    s = st.sec('stop', 8)
    fingerpick(s, 0.5)
    for b, d, p in theme(melody):
        s.n(b, 'dantranh', p, d, 0.55, -0.15, 0.3)
    for start, dur, c in segments(P, 8):
        s.n(start, 'sub', c.bass, dur - 0.2, 0.45, 0.0, 0.0)
    for b in range(8):
        for i in range(8):
            s.n(b * 4 + i * 0.5, 'shaker_dn' if i % 2 == 0 else 'shaker_up', None, 0.25,
                0.3 if i % 2 else 0.2, -0.25, 0.1)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    _riser(s, 'bongo_roll', 0.55)

    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'cymbal', None, 4, 0.5, 0.1, 0.3, raw=True)
    s.n(0, 'cajon_bass', None, 1, 0.7, 0.0, 0.15, raw=True)
    s.n(0, 'claps', None, 1, 0.6, 0.0, 0.25, raw=True)
    s.n(0, 'conga', None, 1, 0.6, 0.2, 0.2, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=2.5)
    s.n(0, 'dantranh_gliss', None, 4, 0.6, 0.0, 0.35, raw=True)

    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    s.strum(0, 'steel', chord('A2 E3 A3 B3 C#4 E4'), 8, 0.75, spread_s=0.03, pan=0.2, send=0.25)
    for i, p in enumerate(chord('A4 C#5 E5 A5')):
        s.n(0.5 + i * 0.5, 'marimba', p, 0.5, 0.9, -0.3, 0.3, raw=True)
    s.n(0, 'bass', midi('A1'), 6, 0.7, 0.0, 0.0, raw=True)
    s.n(2.5, 'chimes_down', None, 4, 0.35, 0.0, 0.35, raw=True)
    return st


def oceania():
    """NZ · AU — indie folk: strummed steel guitar, cajón and claps, a whistle. 98 BPM.

    I–vi–IV–V in G: G | Em7 | Cadd9 | Dsus4 D.
    """
    st = Style('oceania', 'Long White Road', 98, (8, 0.0), room=0.65, damp=0.45, wet=0.85,
               countries=('NZ', 'AU'))
    P = [
        [(0, 4, Chord('G4 B4 D5', 'G1', 'G2 B2 D3 G3 B3 G4'))],
        [(0, 4, Chord('G4 B4 E5', 'E2', 'E2 B2 D3 G3 B3 E4'))],
        [(0, 4, Chord('G4 C5 D5 E5', 'C2', 'C3 E3 G3 D4 G4'))],
        [(0, 2, Chord('G4 A4 D5', 'D2', 'D3 A3 D4 G4')),
         (2, 2, Chord('F#4 A4 D5', 'D2', 'D3 A3 D4 F#4'))],
    ]
    melody = [(0, 1.5, 'D5'), (1.5, 0.5, 'E5'), (2, 1, 'G5'), (3, 1, 'G5'),
              (4, 1.5, 'B5'), (5.5, 0.5, 'A5'), (6, 2, 'G5'),
              (8, 1, 'E5'), (9, 1, 'G5'), (10, 1.5, 'A5'), (11.5, 0.5, 'G5'),
              (12, 2, 'A5'), (14, 1, 'F#5'), (15, 1, 'A5'),
              (16, 1.5, 'D6'), (17.5, 0.5, 'B5'), (18, 1, 'G5'), (19, 1, 'B5'),
              (20, 1.5, 'A5'), (21.5, 0.5, 'G5'), (22, 2, 'E5'),
              (24, 1, 'E5'), (25, 1, 'G5'), (26, 1, 'A5'), (27, 1, 'B5'),
              (28, 2, 'A5'), (30, 1, 'F#5'), (31, 1, 'D5')]

    def chord_at(beat):
        for start, dur, c in segments(P, 4):
            if start <= beat % 16 < start + dur:
                return c
        raise AssertionError(beat)

    def strums(s, vel):
        for b in range(s.bars):
            for i, v in enumerate((0.8, 0.35, 0.55, 0.35, 0.75, 0.35, 0.55, 0.4)):
                beat = b * 4 + i * 0.5
                g = chord_at(beat).gtr
                up = i % 2 == 1
                s.strum(beat, 'steel', g[-4:] if up else g, 0.48, vel * v, up=up, pan=0.25, send=0.18)

    def travis(s, vel):
        for start, dur, c in segments(P, s.bars):
            g = c.gtr
            thumbs, fingers = [g[0], g[2], g[1], g[2]], [g[-1], g[-2], g[-1], g[-3]]
            for i in range(int(dur)):
                s.n(start + i, 'steel', thumbs[i % 4], 0.9, vel * 0.85, 0.15, 0.2)
                s.n(start + i + 0.5, 'steel', fingers[i % 4], 0.9, vel * 0.7, 0.35, 0.22)

    def folk_pad(s, vel):
        for start, dur, c in segments(P, s.bars):
            for i, p in enumerate(c.v):
                s.n(start, 'pad', p - 12, dur, vel, -0.4 + 0.3 * i, 0.4, raw=True)

    def bassline(s, vel):
        for start, dur, c in segments(P, s.bars):
            pat = [(0, 1.4, 0, 0.85), (2, 1.4, 7, 0.75)] if dur == 4 \
                else [(0, 1.4, 0 if start % 4 == 0 else 7, 0.8)]
            for o, d, iv, v in pat:
                s.n(start + o, 'bass', c.bass + iv, d, vel * v, 0.0, 0.0)

    def perc(s, vel, busy):
        for b in range(s.bars):
            o = b * 4
            for k, v in ((0, 0.85), (2, 0.8)) + (((1.5, 0.45),) if busy else ()):
                s.n(o + k, 'cajon_bass', None, 0.5, vel * v, 0.0, 0.15)
            for k in (1, 3):
                s.n(o + k, 'claps', None, 0.5, vel * 0.6, 0.0, 0.25)
            for i in range(8):
                s.n(o + i * 0.5, 'tamb', None, 0.25, vel * (0.4 if i % 2 else 0.18), 0.3, 0.15)

    s = st.sec('intro', 4)
    travis(s, 0.9)
    folk_pad(s, 0.4)

    s = st.sec('travel_a', 4)
    strums(s, 0.8)
    bassline(s, 0.85)
    perc(s, 0.85, False)

    s = st.sec('travel_b', 8)
    strums(s, 0.75)
    bassline(s, 0.85)
    perc(s, 0.9, True)
    for beat, d, nm in melody:
        s.n(beat, 'whistle', midi(nm), d * 0.92, 0.8, 0.0, 0.25)
        if beat >= 16:
            s.n(beat, 'glock', midi(nm) + 12, d, 0.25, -0.3, 0.3)

    s = st.sec('stop', 8)
    travis(s, 0.85)
    folk_pad(s, 0.3)
    for start, dur, c in segments(P, 8):
        s.n(start, 'bass', c.bass, dur - 0.3, 0.5, 0.0, 0.0)
    for b, d, p in theme(melody):
        s.n(b, 'glock', p, d, 0.4, -0.3, 0.4)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    _riser(s, 'tamb_roll', 0.5)
    for k, v in ((0, 0.2), (1, 0.25), (2, 0.3), (2.5, 0.35), (3, 0.4)):
        s.n(k, 'cajon_bass', None, 0.5, v, 0.0, 0.15, raw=True)

    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'cajon_bass', None, 1, 0.75, 0.0, 0.2, raw=True)
    s.n(0, 'claps', None, 1, 0.8, 0.0, 0.3, raw=True)
    s.n(0, 'tamb', None, 1, 0.7, 0.3, 0.15, raw=True)
    s.n(0, 'cymbal', None, 4, 0.4, -0.1, 0.3, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=2.5)
    s.gliss(0, 'glock', chord('G5 A5 B5 D6 E6'), 0.05, 0.45)

    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    s.strum(0, 'steel', chord('G2 B2 D3 G3 B3 G4'), 8, 0.85, spread_s=0.025, pan=0.2, send=0.25)
    s.n(0, 'cajon_bass', None, 1, 0.7, 0.0, 0.2, raw=True)
    s.n(0, 'claps', None, 1, 0.6, 0.0, 0.3, raw=True)
    for i, p in enumerate(chord('G5 B5 D6 G6')):
        s.n(1 + i * 0.5, 'glock', p, 1.0, 0.4, -0.3, 0.4, raw=True)
    s.n(0, 'bass', midi('G1'), 6, 0.7, 0.0, 0.0, raw=True)
    s.n(1, 'chimes_down', None, 4, 0.35, 0.0, 0.35, raw=True)
    return st


STYLES = {'east-asia': east_asia, 'nordic': nordic, 'southeast-asia': southeast_asia,
          'oceania': oceania}
LOOPS = ('intro', 'travel_a', 'travel_b', 'stop')
ONE_SHOTS = ('riser', 'hit_big', 'hit_soft', 'outro')


def style_for_country(code):
    for name, build in STYLES.items():
        if code.upper() in build().countries:
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
        'style': name, 'title': st.title, 'countries': list(st.countries),
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
    fe = sub.add_parser('fetch', help='check out the VCSL recordings the styles use (~0.45 GB)')
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
                  + ', '.join(f'{k} ({"/".join(STYLES[k]().countries)})' for k in STYLES)
                  + ' are decided; what any other country gets is Chiu\'s call')
        print(name)


if __name__ == '__main__':
    main()
