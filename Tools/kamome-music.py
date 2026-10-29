#!/usr/bin/env python3
"""Kamome's own film music: four regional loop sets, composed and synthesised here.

Why this exists (Chiu, 2026-10-29). The film is to have music, and only music
that is free to use. Free music that may be *bundled inside an app* and is not
registered with Content ID is a short list, and every entry on it is someone
else's licence to read. So the music is written here instead: every sound in
this file is synthesised from sine waves and noise. No sample, no sound font
and no recording from anywhere else goes in, so there is no third-party licence
to comply with and nothing for a Content ID claim to match.

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
so switching from one loop to another mid-phrase never clashes.

`arrange` takes a film's events — `{"duration_s": 64, "events": [{"t": 6.5,
"kind": "go"}, ...]}`, kinds `go` (the car moves), `stop` (a stop's photos
open), `crossing` (a crossing's card), `end` (the end card) — and writes one
soundtrack. Each event snaps to the nearest beat and the shift is printed: the
film is not moved here, which is the export's job once this is wired in. A riser
ends on the event's beat and a hit lands on it.

Pure stdlib, like `center-sprites.py`: nothing to install. Styles render in
parallel, one per core.
"""

import argparse
import json
import math
import os
import random
import sys
import wave
from array import array
from multiprocessing import Pool

SR = 44100
TAU = 2.0 * math.pi
NYQ_SAFE = SR * 0.45


def zeros(n):
    return array('d', bytes(8 * n))


# ---------------------------------------------------------------- pitch

_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(name):
    """'F#4' -> 66, 'Bb1' -> 34."""
    pc, i = _PC[name[0]], 1
    while name[i] in '#b':
        pc += 1 if name[i] == '#' else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + pc


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def chord(names):
    return [midi(x) for x in names.split()]


# ---------------------------------------------------------------- instruments
#
# Each takes (frequency in Hz, held seconds, velocity 0-1, seed) and returns a
# mono buffer that includes its own release. Only instruments that use noise
# read the seed; a note picks one of a few seeds, so repeated hits vary a
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


def piano(f, dur, vel, seed):
    """Felt piano: stretched partials, louder is brighter, a soft hammer."""
    rng = random.Random(seed)
    n_on = int(dur * SR)
    n = n_on + int(0.6 * SR)
    out = zeros(n)
    base_tau = min(6.0, 3.0 * (261.6 / f) ** 0.6)
    k_rel = math.exp(-1.0 / (0.12 * SR))
    att = int(0.005 * SR)
    sin = math.sin
    for k in range(1, 9):
        fk = f * k * math.sqrt(1.0 + 0.0004 * k * k)
        if fk > NYQ_SAFE:
            break
        a = (1.0 / k ** 1.5) * (0.35 + 0.65 * vel) ** (k - 1)
        if k > 3:
            a *= 0.45
        tau = base_tau / (1.0 + 0.8 * (k - 1))
        kf = math.exp(-1.0 / (0.15 * tau * SR))
        ks = math.exp(-1.0 / (tau * SR))
        w = TAU * fk / SR
        ph0 = rng.uniform(0, TAU) if k > 1 else 0.0
        ef, es, g = 0.6, 0.4, 1.0
        for t in range(n):
            e = ef + es
            if t < att:
                e *= t / att
            if t >= n_on:
                g *= k_rel
                e *= g
                if e < 1e-5:
                    break
            out[t] += a * e * sin(w * t + ph0)
            ef *= kf
            es *= ks
    m = int(0.012 * SR)
    lp = 0.0
    for t in range(m):
        lp += 0.15 * (rng.uniform(-1, 1) - lp)
        out[t] += 0.25 * vel * lp * (1 - t / m)
    return out


def pluck(f, dur, vel, seed, bright=0.5, t60=3.0):
    """Plucked string: Karplus-Strong, tuned to the cent with an all-pass."""
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
    line = zeros(N)
    lp = 0.0
    for i in range(N):
        lp += coef * (rng.uniform(-1, 1) - lp)
        line[i] = lp
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
    return out


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
GLOCK = ((1.0, 1.0, 1.6), (2.756, 0.30, 0.45), (5.404, 0.12, 0.18), (8.933, 0.05, 0.08))
CHIME = ((1.0, 1.0, 3.0), (2.76, 0.35, 1.2), (5.40, 0.18, 0.5), (8.93, 0.08, 0.25))
MARIMBA = ((1.0, 1.0, 0.5), (4.0, 0.22, 0.08), (10.0, 0.05, 0.02))
KALIMBA = ((1.0, 1.0, 1.1), (2.0, 0.06, 0.4), (5.9, 0.22, 0.05))


def mallet(f, dur, vel, seed, partials=GLOCK, noise=0.05):
    """Struck bars: glockenspiel, chimes, marimba, kalimba — decaying partials."""
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


def _hp_coef(fc):
    return math.exp(-TAU * fc / SR)


def _lp_coef(fc):
    return 1.0 - math.exp(-TAU * fc / SR)


def kick(f, dur, vel, seed, f_start=150.0, f_end=48.0, sweep=0.035, decay=0.22,
         click=0.15, thump=0.0, length=0.6):
    """Kick, stomp, boom: a sine falling in pitch, a click, optionally a thump."""
    rng = random.Random(seed)
    n = int(length * SR)
    out = zeros(n)
    ks = math.exp(-1.0 / (sweep * SR))
    kd = math.exp(-1.0 / (decay * SR))
    kt = math.exp(-1.0 / (0.04 * SR))
    a_lp = _lp_coef(250.0)
    m = int(0.003 * SR)
    ph, s, e, et, lp = 0.0, 1.0, 1.0, 1.0, 0.0
    sin, tanh = math.sin, math.tanh
    for t in range(n):
        ph += TAU * (f_end + (f_start - f_end) * s) / SR
        y = sin(ph) * e
        nz = rng.uniform(-1, 1)
        if t < m:
            y += click * nz * (1 - t / m)
        if thump:
            lp += a_lp * (nz - lp)
            y += thump * lp * et * 3.0
        out[t] = tanh(1.5 * y)
        s *= ks
        e *= kd
        et *= kt
    return out


def snare(f, dur, vel, seed, tone=0.6, lp_hz=7000.0, decay=0.14, length=0.4):
    """Snare: a two-mode drum head and band-passed wires."""
    rng = random.Random(seed)
    n = int(length * SR)
    out = zeros(n)
    a_lp, a_hp = _lp_coef(lp_hz), _hp_coef(900.0)
    kt = math.exp(-1.0 / (0.07 * SR))
    kn = math.exp(-1.0 / (decay * SR))
    w = TAU * 185.0 / SR
    et, en, lp, hy, hx = 1.0, 1.0, 0.0, 0.0, 0.0
    sin = math.sin
    for t in range(n):
        nz = rng.uniform(-1, 1)
        hy = a_hp * (hy + nz - hx)
        hx = nz
        lp += a_lp * (hy - lp)
        out[t] = tone * et * (sin(w * t) + 0.5 * sin(1.6 * w * t)) + en * lp * 1.4
        et *= kt
        en *= kn
    return out


def rim(f, dur, vel, seed):
    """Rim click: two short modes and a tick."""
    rng = random.Random(seed)
    n = int(0.12 * SR)
    out = zeros(n)
    k1 = math.exp(-1.0 / (0.012 * SR))
    k2 = math.exp(-1.0 / (0.025 * SR))
    w1, w2 = TAU * 1700.0 / SR, TAU * 520.0 / SR
    e1, e2 = 1.0, 1.0
    m = int(0.002 * SR)
    for t in range(n):
        y = 0.6 * e1 * math.sin(w1 * t) + 0.5 * e2 * math.sin(w2 * t)
        if t < m:
            y += 0.5 * rng.uniform(-1, 1)
        out[t] = y
        e1 *= k1
        e2 *= k2
    return out


def clap(f, dur, vel, seed, length=0.35):
    """Hand clap: three quick bursts and a short room."""
    rng = random.Random(seed)
    n = int(length * SR)
    out = zeros(n)
    a_lp, a_hp = _lp_coef(2600.0), _hp_coef(850.0)
    bursts = (0, int(0.010 * SR), int(0.020 * SR))
    tail0 = int(0.028 * SR)
    lp, hy, hx = 0.0, 0.0, 0.0
    exp = math.exp
    for t in range(n):
        nz = rng.uniform(-1, 1)
        hy = a_hp * (hy + nz - hx)
        hx = nz
        lp += a_lp * (hy - lp)
        e = 0.0
        for b in bursts:
            if t >= b:
                e += exp(-(t - b) / (0.005 * SR))
        if t >= tail0:
            e += 0.6 * exp(-(t - tail0) / (0.09 * SR))
        out[t] = lp * e * 2.5
    return out


_METAL = (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)


def hat(f, dur, vel, seed, decay=0.035, lp_hz=None):
    """Hi-hat: high-passed noise over a metallic square cluster."""
    rng = random.Random(seed)
    n = int((decay * 6 + 0.01) * SR)
    out = zeros(n)
    a_hp = _hp_coef(7000.0)
    a_lp = _lp_coef(lp_hz) if lp_hz else 1.0
    k = math.exp(-1.0 / (decay * SR))
    ws = [TAU * m * 8.0 / SR for m in _METAL]
    e, h1, x1, h2, x2, lp = 1.0, 0.0, 0.0, 0.0, 0.0, 0.0
    sin = math.sin
    att = int(0.001 * SR)
    for t in range(n):
        metal = 0.0
        for w in ws:
            metal += 1.0 if sin(w * t) > 0 else -1.0
        x = 0.6 * rng.uniform(-1, 1) + 0.4 * metal / 6.0
        h1 = a_hp * (h1 + x - x1)
        x1 = x
        h2 = a_hp * (h2 + h1 - x2)
        x2 = h1
        lp += a_lp * (h2 - lp)
        out[t] = lp * e * (t / att if t < att else 1.0) * 2.0
        e *= k
    return out


def shaker(f, dur, vel, seed):
    """Shaker: high noise that swells for a moment, then falls."""
    rng = random.Random(seed)
    n = int(0.14 * SR)
    out = zeros(n)
    a_hp = _hp_coef(5000.0)
    k = math.exp(-1.0 / (0.04 * SR))
    att = int(0.012 * SR)
    e, hy, hx = 1.0, 0.0, 0.0
    for t in range(n):
        nz = rng.uniform(-1, 1)
        hy = a_hp * (hy + nz - hx)
        hx = nz
        if t < att:
            out[t] = hy * (t / att) * 1.6
        else:
            out[t] = hy * e * 1.6
            e *= k
    return out


def tamb(f, dur, vel, seed):
    """Tambourine: noise and a few jingle partials."""
    rng = random.Random(seed)
    n = int(0.3 * SR)
    out = zeros(n)
    a_hp = _hp_coef(6000.0)
    kn = math.exp(-1.0 / (0.07 * SR))
    kj = math.exp(-1.0 / (0.12 * SR))
    jingles = [(TAU * fj / SR, rng.uniform(0, TAU)) for fj in (5600.0, 6900.0, 8200.0, 9700.0)]
    en, ej, hy, hx = 1.0, 1.0, 0.0, 0.0
    sin = math.sin
    for t in range(n):
        nz = rng.uniform(-1, 1)
        hy = a_hp * (hy + nz - hx)
        hx = nz
        j = 0.0
        for w, p in jingles:
            j += sin(w * t + p)
        out[t] = 1.4 * hy * en + 0.12 * j * ej
        en *= kn
        ej *= kj
    return out


def crash(f, dur, vel, seed, decay=1.6, lp_hz=None, ping=0.0, length=None):
    """Cymbal (crash or ride): noise and an inharmonic metal cluster."""
    rng = random.Random(seed)
    n = int((length or min(4.0, decay * 3.0)) * SR)
    out = zeros(n)
    a_hp = _hp_coef(3000.0)
    a_lp = _lp_coef(lp_hz) if lp_hz else 1.0
    kn = math.exp(-1.0 / (decay * SR))
    km = math.exp(-1.0 / (decay * 0.7 * SR))
    kp = math.exp(-1.0 / (0.4 * SR))
    partials = [(TAU * rng.uniform(3000.0, 9000.0) / SR, rng.uniform(0, TAU)) for _ in range(8)]
    wp = TAU * 3150.0 / SR
    en, em, ep_, hy, hx, lp = 1.0, 1.0, 1.0, 0.0, 0.0, 0.0
    att = int(0.002 * SR)
    sin = math.sin
    for t in range(n):
        nz = rng.uniform(-1, 1)
        hy = a_hp * (hy + nz - hx)
        hx = nz
        m = 0.0
        for w, p in partials:
            m += sin(w * t + p)
        x = hy * en * 1.2 + 0.05 * m * em
        lp += a_lp * (x - lp)
        y = lp + ping * ep_ * sin(wp * t)
        out[t] = y * (t / att if t < att else 1.0)
        en *= kn
        em *= km
        ep_ *= kp
    return out


def revcrash(f, dur, vel, seed):
    """Reverse cymbal: a crash played backwards, so it swells into the beat."""
    fwd = crash(f, dur, vel, seed, decay=1.1, lp_hz=9000.0, length=dur)
    out = array('d', reversed(fwd))
    n = len(out)
    for t in range(n):
        out[t] *= (t / n) ** 1.5
    return out


def tom(f, dur, vel, seed, f0=95.0):
    """Floor tom / timpani-ish: a slower, rounder fall than a kick."""
    return kick(f, dur, vel, seed, f_start=f0 * 1.6, f_end=f0, sweep=0.06,
                decay=0.45, click=0.05, length=1.2)


def conga(f, dur, vel, seed, f0=330.0, slap=0.0):
    """Conga: a membrane with an inharmonic overtone and a slap of noise."""
    rng = random.Random(seed)
    n = int(0.35 * SR)
    out = zeros(n)
    ks = math.exp(-1.0 / (0.02 * SR))
    kd = math.exp(-1.0 / (0.17 * SR))
    ko = math.exp(-1.0 / (0.05 * SR))
    a_hp = _hp_coef(1000.0)
    m = int(0.006 * SR)
    ph, s, e, eo, hy, hx = 0.0, 1.0, 1.0, 1.0, 0.0, 0.0
    sin = math.sin
    for t in range(n):
        ph += TAU * f0 * (1.0 + 0.15 * s) / SR
        y = sin(ph) * e + 0.25 * sin(1.59 * ph) * eo
        if t < m:
            nz = rng.uniform(-1, 1)
            hy = a_hp * (hy + nz - hx)
            hx = nz
            y += (0.15 + slap) * hy * (1 - t / m) * 2.0
        out[t] = y
        s *= ks
        e *= kd
        eo *= ko
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


# name: (render function, its options, mix gain, seed variants, is a drum)
INST = {
    'ep': (ep, {}, 0.30, 1, False),
    'piano': (piano, {}, 0.36, 1, False),
    'nylon': (pluck, dict(bright=0.42, t60=2.2), 1.10, 3, False),
    'steel': (pluck, dict(bright=0.8, t60=3.5), 0.95, 3, False),
    'mando': (pluck, dict(bright=0.95, t60=1.2), 0.80, 3, False),
    'bass': (bass, {}, 0.46, 1, False),
    'sub': (bass, dict(bright=0.12, attack=0.03), 0.50, 1, False),
    'pad': (pad, {}, 0.11, 1, False),
    'shimmer': (pad, dict(attack=1.6, release=2.0, nh_cap=4, detune_c=11.0), 0.07, 1, False),
    'flute': (wind, {}, 0.20, 1, False),
    'panflute': (wind, dict(breath=0.2, chiff=0.6, vib=0.003, h2=0.06, h3=0.08), 0.19, 1, False),
    'whistle': (wind, dict(breath=0.04, chiff=0.1, vib=0.007, vib_hz=6.0, h2=0.02, h3=0.0,
                           attack=0.03), 0.22, 1, False),
    'glock': (mallet, dict(partials=GLOCK), 0.22, 1, False),
    'chime': (mallet, dict(partials=CHIME), 0.11, 1, False),
    'marimba': (mallet, dict(partials=MARIMBA, noise=0.2), 0.25, 1, False),
    'kalimba': (mallet, dict(partials=KALIMBA, noise=0.1), 0.26, 1, False),
    'kick': (kick, {}, 0.80, 4, True),
    'kick_lofi': (kick, dict(f_start=120.0, f_end=50.0, decay=0.2, click=0.04), 0.78, 4, True),
    'stomp': (kick, dict(f_start=100.0, f_end=40.0, decay=0.3, click=0.0, thump=0.5), 0.85, 4, True),
    'boom': (kick, dict(f_start=90.0, f_end=38.0, sweep=0.08, decay=0.9, click=0.0, length=2.5),
             0.75, 2, True),
    'snare': (snare, {}, 1.05, 4, True),
    'snare_lofi': (snare, dict(lp_hz=3800.0, tone=0.8), 1.00, 4, True),
    'rim': (rim, {}, 0.28, 4, True),
    'clap': (clap, {}, 1.60, 4, True),
    'hat': (hat, {}, 1.40, 4, True),
    'hat_lofi': (hat, dict(decay=0.03, lp_hz=6500.0), 1.60, 4, True),
    'ohat': (hat, dict(decay=0.28), 0.70, 4, True),
    'shaker': (shaker, {}, 0.55, 4, True),
    'tamb': (tamb, {}, 0.85, 4, True),
    'crash': (crash, {}, 0.32, 2, True),
    'crash_dark': (crash, dict(decay=1.4, lp_hz=5000.0), 0.36, 2, True),
    'ride': (crash, dict(decay=0.6, ping=0.25, length=1.6), 0.30, 4, True),
    'revcrash': (revcrash, {}, 0.30, 1, True),
    'tom': (tom, {}, 0.60, 2, True),
    'conga_hi': (conga, dict(f0=330.0), 0.48, 4, True),
    'conga_lo': (conga, dict(f0=220.0), 0.50, 4, True),
    'conga_slap': (conga, dict(f0=310.0, slap=0.6), 0.42, 4, True),
    'vinyl': (vinyl, {}, 1.40, 1, False),
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


def east_asia():
    """JP · TW · KR — light lo-fi, city pop, nylon guitar. 90 BPM, swung 8ths.

    The progression is the 'Marunouchi' city-pop turn, IVmaj7–III7–vim7–vm7 I7,
    in F: Bbmaj9 | A9 | Dm9 | Cm9 F9, voiced rootless on the electric piano.
    """
    st = Style('east-asia', 'Neon Rain', 90, (8, 0.06), room=0.55, damp=0.5, wet=0.8,
               countries=('JP', 'TW', 'KR'))
    P = [
        [(0, 4, Chord('D4 F4 A4 C5', 'Bb1'))],
        [(0, 4, Chord('C#4 G4 B4 E5', 'A1'))],
        [(0, 4, Chord('F4 A4 C5 E5', 'D2'))],
        [(0, 2, Chord('Eb4 G4 Bb4 D5', 'C2')), (2, 2, Chord('A3 Eb4 G4 C5', 'F1'))],
    ]

    def comp(s, vel):
        for start, dur, c in segments(P, s.bars):
            hits = [(0, 1.4, 1.0), (1.5, 0.45, 0.55), (2.5, 1.3, 0.8)] if dur == 4 \
                else [(0, 1.3, 0.95), (1.5, 0.4, 0.5)]
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
            o = b * 4
            last = b % 4 == 3
            for k, v in ((0, 0.95), (1.5, 0.55), (2.5, 0.8)) + (((3.5, 0.5),) if last else ()):
                s.n(o + k, 'kick_lofi', None, 0.5, vel * v, 0.0, 0.03)
            for k in (1, 3):
                s.n(o + k, 'snare_lofi', None, 0.5, vel * 0.85, 0.0, 0.12)
            for i, v in enumerate((0.55, 0.3, 0.45, 0.3, 0.55, 0.3, 0.45, 0.35)):
                if last and i == 7:
                    s.n(o + 3.5, 'ohat', None, 0.5, vel * 0.5, 0.2, 0.05)
                else:
                    s.n(o + i * 0.5, 'hat_lofi', None, 0.25, vel * v, 0.2, 0.04)

    def arps(s, vel):
        for start, dur, c in segments(P, s.bars):
            idx = [0, 1, 2, 3, 2, 1, 2, 3] if dur == 4 else [0, 1, 2, 3]
            for i, j in enumerate(idx):
                s.n(start + i * 0.5, 'nylon', c.v[j], 0.9, vel * (0.9 if i % 2 == 0 else 0.7),
                    0.35, 0.2)

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

    s = st.sec('intro', 4, lp_hz=1100.0)
    for start, dur, c in segments(P, 4):
        s.strum(start, 'ep', c.v, dur - 0.1, 0.7, spread_s=0.03, pan=-0.1, send=0.3)
    _crackle(s)

    s = st.sec('travel_a', 4)
    comp(s, 0.75)
    bassline(s, 0.9)
    drums(s, 0.9)
    _crackle(s)

    s = st.sec('travel_b', 8)
    comp(s, 0.65)
    bassline(s, 0.9)
    drums(s, 0.95)
    arps(s, 0.45)
    for b, d, nm in melody:
        s.n(b, 'flute', midi(nm), d * 0.95, 0.8, 0.05, 0.3)
    _crackle(s)

    s = st.sec('stop', 8)
    for start, dur, c in segments(P, 8):
        s.strum(start, 'ep', c.v, dur - 0.1, 0.45, spread_s=0.02, pan=-0.15, send=0.3)
        s.n(start, 'bass', c.bass, dur - 0.3, 0.5, 0.0, 0.0)
    arps(s, 0.6)
    for b in range(8):
        for i in range(8):
            s.n(b * 4 + i * 0.5, 'shaker', None, 0.25, 0.35 if i % 2 else 0.2, -0.25, 0.05)
    _crackle(s)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    s.n(0, 'revcrash', None, 4, 0.75, 0.0, 0.1, raw=True)
    for i in range(8):
        s.n(2 + i * 0.25, 'hat_lofi', None, 0.25, 0.15 + 0.05 * i, 0.2, 0.05, raw=True)
    for i in range(4):
        s.n(3 + i * 0.25, 'snare_lofi', None, 0.25, 0.25 + 0.12 * i, 0.0, 0.1, raw=True)

    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'crash_dark', None, 4, 0.8, 0.1, 0.25, raw=True)
    s.n(0, 'kick_lofi', None, 1, 1.0, 0.0, 0.05, raw=True)
    s.n(0, 'snare_lofi', None, 1, 0.6, 0.0, 0.2, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=3.0)
    s.gliss(0, 'chime', chord('C6 D6 F6 A6 C7'), 0.06, 0.5)

    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    s.strum(0, 'ep', chord('A4 C5 E5 G5'), 6, 0.6, spread_s=0.04, pan=-0.1, send=0.3)
    s.strum(0, 'nylon', chord('F3 C4 F4 A4 C5 E5'), 7, 0.6, spread_s=0.05, pan=0.3, send=0.25)
    s.n(0, 'bass', midi('F1'), 5, 0.7, 0.0, 0.0, raw=True)
    s.gliss(0.5, 'chime', chord('C6 D6 F6 A6 C7'), 0.08, 0.4)
    s.n(0, 'crash_dark', None, 4, 0.35, 0.1, 0.25, raw=True)
    return st


def nordic():
    """IS · NO — ambient, felt piano, post-rock. 80 BPM, straight, a big room.

    I–V–vi–IV in D, opened up: Dadd9 | A/C# | Bm7 | Gmaj7(#11).
    """
    st = Style('nordic', 'Northern Light', 80, (8, 0.0), room=0.88, damp=0.3, wet=1.15,
               countries=('IS', 'NO'))
    P = [
        [(0, 4, Chord('A3 D4 E4 F#4', 'D2'))],
        [(0, 4, Chord('A3 C#4 E4 B4', 'C#2'))],
        [(0, 4, Chord('F#3 B3 D4 A4', 'B1'))],
        [(0, 4, Chord('B3 D4 F#4 C#5', 'G1'))],
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
            seq = [c.bass + 12] + c.v + c.v[2::-1]
            for i, p in enumerate(seq):
                acc = 1.0 if i in (0, 4) else 0.75
                s.n(start + i * 0.5, 'piano', p, 1.5, vel * acc, -0.2 + 0.06 * i, 0.4)

    def low(s, vel):
        for start, dur, c in segments(P, s.bars):
            s.n(start, 'sub', c.bass, dur - 0.1, vel, 0.0, 0.0)

    trem = [(0, 2, 'F#5'), (2, 2, 'A5'), (4, 4, 'E5'), (8, 2, 'D5'), (10, 2, 'F#5'), (12, 4, 'F#5'),
            (16, 2, 'A5'), (18, 2, 'B5'), (20, 4, 'A5'), (24, 2, 'F#5'), (26, 2, 'D5'), (28, 4, 'E5')]

    s = st.sec('intro', 4)
    pads(s, 0.6, 0.55)
    for start, dur, c in segments(P, 4):
        s.n(start, 'piano', c.v[3] + 12, 2.0, 0.55, 0.25, 0.55)
        s.n(start + 2, 'piano', c.v[2] + 12, 2.0, 0.5, -0.25, 0.55)
        s.n(start, 'sub', c.bass, dur - 0.1, 0.3, 0.0, 0.0)

    s = st.sec('travel_a', 4)
    pads(s, 0.4, 0.0)
    arps(s, 0.55)
    low(s, 0.6)
    for b in range(4):
        o = b * 4
        s.n(o, 'kick', None, 0.5, 0.8, 0.0, 0.08)
        s.n(o + 1.5, 'kick', None, 0.5, 0.45, 0.0, 0.08)
        s.n(o + 2, 'snare', None, 0.5, 0.45, 0.0, 0.4)
        for i in range(8):
            s.n(o + i * 0.5, 'shaker', None, 0.25, 0.3 if i % 2 else 0.18, -0.3, 0.15)

    s = st.sec('travel_b', 8)
    pads(s, 0.42, 0.35)
    arps(s, 0.5)
    low(s, 0.55)
    for b in range(8):
        o = b * 4
        for k, v in ((0, 0.9), (1.5, 0.6), (2.5, 0.5)):
            s.n(o + k, 'kick', None, 0.5, v, 0.0, 0.08)
        s.n(o + 2, 'snare', None, 0.5, 0.85, 0.0, 0.45)
        for i in range(8):
            s.n(o + i * 0.5, 'ride', None, 0.5, 0.45 if i % 2 == 0 else 0.3, 0.3, 0.2)
        if b in (0, 4):
            s.n(o, 'crash', None, 4, 0.55 if b == 0 else 0.4, -0.3, 0.4)
        for start, dur, c in segments(P, 8)[b:b + 1]:
            for i in range(8):
                s.n(start + i * 0.5, 'bass', c.bass + 12, 0.45, 0.5 if i % 2 == 0 else 0.38, 0.0, 0.0)
    for beat, d, nm in trem:
        for k in range(int(d * 4)):
            s.n(beat + k * 0.25, 'steel', midi(nm), 0.3, 0.65 if k % 2 == 0 else 0.5, 0.35, 0.4)
    for beat, d, nm in trem[6:]:
        for e in range(3):
            s.n(beat + e * 0.75, 'glock', midi(nm) + 12, 1.0, 0.55 * 0.4 ** e,
                -0.35 if e % 2 == 0 else 0.35, 0.45)

    s = st.sec('stop', 8)
    pads(s, 0.4, 0.45)
    for start, dur, c in segments(P, 8):
        s.n(start, 'piano', c.bass + 12, 2.0, 0.4, -0.25, 0.45)
        s.n(start + 2, 'piano', c.bass + 19, 2.0, 0.32, -0.25, 0.45)
        s.n(start, 'sub', c.bass, dur - 0.1, 0.35, 0.0, 0.0)
    for beat, d, nm in [(0, 1.5, 'A4'), (1.5, 0.5, 'F#4'), (2, 2, 'E4'), (4, 1.5, 'E4'),
                        (5.5, 0.5, 'C#5'), (6, 2, 'B4'), (8, 1.5, 'D5'), (9.5, 0.5, 'B4'),
                        (10, 2, 'F#4'), (12, 1, 'F#4'), (13, 1, 'A4'), (14, 2, 'B4'),
                        (16, 1.5, 'A4'), (17.5, 0.5, 'F#4'), (18, 2, 'E4'), (20, 1.5, 'E4'),
                        (21.5, 0.5, 'A4'), (22, 2, 'B4'), (24, 1.5, 'D5'), (25.5, 0.5, 'E5'),
                        (26, 2, 'F#5'), (28, 4, 'E5')]:
        s.n(beat, 'piano', midi(nm), d, 0.55, 0.15, 0.5)

    s = st.sec('riser', 1, loop=False, tail_s=0.8, anchor_beats=4)
    s.n(0, 'revcrash', None, 4, 0.7, 0.0, 0.3, raw=True)
    for i in range(16):
        s.n(i * 0.25, 'snare', None, 0.25, 0.08 + 0.035 * i, 0.0, 0.35, raw=True)

    s = st.sec('hit_big', 1, loop=False, tail_s=4.0)
    s.n(0, 'crash', None, 4, 0.75, -0.2, 0.5, raw=True)
    s.n(0, 'tom', None, 2, 0.9, 0.0, 0.3, raw=True)
    s.n(0, 'boom', None, 2, 0.7, 0.0, 0.2, raw=True)
    s.n(0, 'snare', None, 1, 0.5, 0.0, 0.5, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=3.0)
    s.gliss(0, 'glock', chord('D6 E6 F#6 A6'), 0.07, 0.42, send=0.6)

    s = st.sec('outro', 2, loop=False, tail_s=5.0)
    s.strum(0, 'piano', chord('D2 A2 D3 F#3 A3 E4 F#4 A4'), 8, 0.6, spread_s=0.05, send=0.5)
    for i, p in enumerate(chord('A3 D4 E4 F#4')):
        s.n(0, 'pad', p, 6, 0.4, -0.45 + 0.3 * i, 0.5, raw=True)
    s.n(0, 'shimmer', midi('F#5'), 6, 0.5, -0.5, 0.7, raw=True)
    s.n(0, 'shimmer', midi('A5'), 6, 0.5, 0.5, 0.7, raw=True)
    s.n(1, 'glock', midi('D6'), 2, 0.4, 0.3, 0.6, raw=True)
    s.n(0, 'crash', None, 4, 0.35, -0.2, 0.5, raw=True)
    return st


def southeast_asia():
    """VN · TH — warm acoustic, light tropical. 100 BPM, a touch of 16th swing.

    I–vi–IV–V in A: A(add9) | F#m7 | Dmaj7 | Esus4 E.
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
                strings = g if d == 'D' else g[-4:]
                s.strum(beat, 'steel', strings, (nxt - o) * 0.95, vel * v, up=(d == 'U'),
                        pan=0.3, send=0.18)

    def fingerpick(s, vel):
        for start, dur, c in segments(P, s.bars):
            g = c.gtr
            idx = [0, 2, 3, 4, 1, 3, 4, 3]
            for i in range(int(dur * 2)):
                j = min(idx[i % 8], len(g) - 1)
                s.n(start + i * 0.5, 'nylon', g[j], 1.2, vel * (0.9 if i % 2 == 0 else 0.7), 0.3, 0.22)

    def kalimba_line(s, vel):
        for start, dur, c in segments(P, s.bars):
            if dur == 4:
                for o, j in ((0, 3), (0.75, 1), (1.5, 2), (2.5, 3), (3, 0)):
                    s.n(start + o, 'kalimba', c.v[min(j, len(c.v) - 1)], 0.5, vel, -0.3, 0.3)
            else:
                for o, j in ((0, 2), (0.75, 1), (1.5, 0)):
                    s.n(start + o, 'kalimba', c.v[j], 0.5, vel, -0.3, 0.3)

    def bassline(s, vel):
        for start, dur, c in segments(P, s.bars):
            pat = [(0, 0.9, 0, 0.9), (1.5, 0.4, 0, 0.6), (2.5, 0.4, 7, 0.55), (3, 0.9, 0, 0.75)] \
                if dur == 4 else [(0, 0.9, 0, 0.9), (1.5, 0.4, 7, 0.55)]
            for o, d, iv, v in pat:
                s.n(start + o, 'bass', c.bass + iv, d, vel * v, 0.0, 0.0)

    def drums(s, vel):
        for b in range(s.bars):
            o = b * 4
            for k in range(4):
                s.n(o + k, 'kick', None, 0.5, vel * (0.6 if k % 2 == 0 else 0.5), 0.0, 0.04)
            for k in (1, 3):
                s.n(o + k, 'clap', None, 0.5, vel * 0.55, 0.0, 0.2)
            for i, v in enumerate((0.3, 0.14, 0.22, 0.14) * 4):
                s.n(o + i * 0.25, 'shaker', None, 0.25, vel * v, -0.25, 0.05)
            for k in (0.5, 1.5, 2.5, 3.5):
                s.n(o + k, 'ohat', None, 0.5, vel * 0.3, 0.2, 0.05)

    def marimba_offbeats(s, vel):
        for b in range(s.bars):
            for o in (0.5, 1.5, 2.5, 3.5):
                c = chord_at(b * 4 + o)
                for p in c.v[-2:]:
                    s.n(b * 4 + o, 'marimba', p, 0.3, vel, -0.3, 0.2)

    s = st.sec('intro', 4)
    kalimba_line(s, 0.5)
    for start, dur, c in segments(P, 4):
        for i, p in enumerate(c.v):
            s.n(start, 'pad', p, dur, 0.3, -0.4 + 0.25 * i, 0.4, raw=True)

    s = st.sec('travel_a', 4)
    strums(s, 0.85)
    bassline(s, 0.9)
    drums(s, 0.9)
    marimba_offbeats(s, 0.45)

    s = st.sec('travel_b', 8)
    strums(s, 0.8)
    bassline(s, 0.9)
    drums(s, 0.95)
    marimba_offbeats(s, 0.35)
    for b in range(8):
        for o, inst, v in ((0.75, 'conga_lo', 0.5), (1.5, 'conga_hi', 0.55), (2.5, 'conga_hi', 0.5),
                           (2.75, 'conga_lo', 0.45), (3.5, 'conga_slap', 0.6)):
            s.n(b * 4 + o, inst, None, 0.25, v, 0.35 if inst == 'conga_hi' else -0.1, 0.12)
    for beat, d, nm in [(0, 0.5, 'C#5'), (0.5, 0.5, 'E5'), (1, 1, 'F#5'), (2, 0.5, 'E5'),
                        (2.5, 1.5, 'C#5'), (4.5, 0.5, 'A4'), (5, 0.5, 'C#5'), (5.5, 0.5, 'E5'),
                        (6, 2, 'F#5'), (8, 0.5, 'A5'), (8.5, 0.5, 'F#5'), (9, 1, 'E5'),
                        (10, 0.5, 'C#5'), (10.5, 1.5, 'E5'), (12, 1, 'B4'), (13, 1, 'C#5'),
                        (14, 2, 'B4'), (16, 0.5, 'E5'), (16.5, 0.5, 'F#5'), (17, 1, 'A5'),
                        (18, 0.5, 'F#5'), (18.5, 1.5, 'E5'), (20.5, 0.5, 'C#5'), (21, 0.5, 'E5'),
                        (21.5, 0.5, 'F#5'), (22, 2, 'A5'), (24, 1, 'F#5'), (25, 0.5, 'E5'),
                        (25.5, 0.5, 'C#5'), (26, 2, 'E5'), (28, 1.5, 'B4'), (29.5, 0.5, 'C#5'),
                        (30, 2, 'E5')]:
        s.n(beat, 'panflute', midi(nm), d * 0.95, 0.8, 0.05, 0.3)

    s = st.sec('stop', 8)
    fingerpick(s, 0.6)
    kalimba_line(s, 0.4)
    for start, dur, c in segments(P, 8):
        s.n(start, 'sub', c.bass, dur - 0.2, 0.45, 0.0, 0.0)
    for b in range(8):
        for i in range(8):
            s.n(b * 4 + i * 0.5, 'shaker', None, 0.25, 0.3 if i % 2 else 0.18, -0.25, 0.05)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    s.n(0, 'revcrash', None, 4, 0.55, 0.0, 0.15, raw=True)
    for i in range(16):
        s.n(i * 0.25, 'shaker', None, 0.25, 0.08 + 0.02 * i, -0.25, 0.05, raw=True)
    for i in range(8):
        s.n(2 + i * 0.25, 'conga_hi' if i % 2 == 0 else 'conga_lo', None, 0.25, 0.2 + 0.06 * i,
            0.1, 0.1, raw=True)

    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'crash', None, 4, 0.55, 0.1, 0.3, raw=True)
    s.n(0, 'kick', None, 1, 0.8, 0.0, 0.05, raw=True)
    s.n(0, 'clap', None, 1, 0.6, 0.0, 0.25, raw=True)
    s.n(0, 'conga_slap', None, 1, 0.6, 0.2, 0.15, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=2.0)
    s.gliss(0, 'marimba', chord('A4 C#5 E5 F#5 A5'), 0.035, 0.5)

    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    s.strum(0, 'steel', chord('A2 E3 A3 B3 C#4 E4'), 8, 0.75, spread_s=0.03, pan=0.2, send=0.25)
    for i, p in enumerate(chord('A4 C#5 E5 A5')):
        s.n(0.5 + i * 0.5, 'marimba', p, 0.5, 0.5, -0.3, 0.3, raw=True)
    s.n(0, 'bass', midi('A1'), 6, 0.7, 0.0, 0.0, raw=True)
    s.n(2.5, 'chime', midi('E6'), 2, 0.4, 0.3, 0.4, raw=True)
    s.n(0, 'crash', None, 4, 0.3, 0.1, 0.3, raw=True)
    return st


def oceania():
    """NZ · AU — indie folk: strummed steel guitar, stomp and clap, a whistle. 98 BPM.

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

    def chord_at(beat):
        for start, dur, c in segments(P, 4):
            if start <= beat % 16 < start + dur:
                return c
        raise AssertionError(beat)

    def strums(s, vel):
        vels = (0.8, 0.35, 0.55, 0.35, 0.75, 0.35, 0.55, 0.4)
        for b in range(s.bars):
            for i, v in enumerate(vels):
                beat = b * 4 + i * 0.5
                g = chord_at(beat).gtr
                up = i % 2 == 1
                s.strum(beat, 'steel', g[-4:] if up else g, 0.48, vel * v, up=up, pan=0.25, send=0.18)

    def travis(s, vel):
        for start, dur, c in segments(P, s.bars):
            g = c.gtr
            thumbs = [g[0], g[2], g[1], g[2]]
            fingers = [g[-1], g[-2], g[-1], g[-3]]
            for i in range(int(dur)):
                s.n(start + i, 'steel', thumbs[i % 4], 0.9, vel * 0.85, 0.15, 0.2)
                s.n(start + i + 0.5, 'steel', fingers[i % 4], 0.9, vel * 0.7, 0.35, 0.22)

    def bassline(s, vel):
        for start, dur, c in segments(P, s.bars):
            pat = [(0, 1.4, 0, 0.85), (2, 1.4, 7, 0.75)] if dur == 4 else [(0, 1.4, 0 if start % 4 == 0 else 7, 0.8)]
            for o, d, iv, v in pat:
                s.n(start + o, 'bass', c.bass + iv, d, vel * v, 0.0, 0.0)

    def stomp_clap(s, vel, busy):
        for b in range(s.bars):
            o = b * 4
            for k in (0, 2) + ((1.5,) if busy else ()):
                s.n(o + k, 'stomp', None, 0.5, vel * (0.9 if k in (0, 2) else 0.55), 0.0, 0.15)
            for k in (1, 3):
                s.n(o + k, 'clap', None, 0.5, vel * 0.75, -0.15, 0.25)
                if busy:
                    s.n(o + k, 'clap', None, 0.5, vel * 0.5, 0.25, 0.25)
            for i in range(8):
                s.n(o + i * 0.5, 'tamb', None, 0.25, vel * (0.4 if i % 2 else 0.18), 0.3, 0.1)

    def folk_pad(s, vel):
        for start, dur, c in segments(P, s.bars):
            for i, p in enumerate(c.v):
                s.n(start, 'pad', p - 12, dur, vel, -0.4 + 0.3 * i, 0.4, raw=True)

    melody = [(0, 1.5, 'D5'), (1.5, 0.5, 'E5'), (2, 1, 'G5'), (3, 1, 'G5'),
              (4, 1.5, 'B5'), (5.5, 0.5, 'A5'), (6, 2, 'G5'),
              (8, 1, 'E5'), (9, 1, 'G5'), (10, 1.5, 'A5'), (11.5, 0.5, 'G5'),
              (12, 2, 'A5'), (14, 1, 'F#5'), (15, 1, 'A5'),
              (16, 1.5, 'D6'), (17.5, 0.5, 'B5'), (18, 1, 'G5'), (19, 1, 'B5'),
              (20, 1.5, 'A5'), (21.5, 0.5, 'G5'), (22, 2, 'E5'),
              (24, 1, 'E5'), (25, 1, 'G5'), (26, 1, 'A5'), (27, 1, 'B5'),
              (28, 2, 'A5'), (30, 1, 'F#5'), (31, 1, 'D5')]

    s = st.sec('intro', 4)
    travis(s, 0.95)
    folk_pad(s, 0.4)

    s = st.sec('travel_a', 4)
    strums(s, 0.85)
    bassline(s, 0.9)
    stomp_clap(s, 0.9, False)

    s = st.sec('travel_b', 8)
    strums(s, 0.8)
    bassline(s, 0.9)
    stomp_clap(s, 0.95, True)
    for beat, d, nm in melody:
        s.n(beat, 'whistle', midi(nm), d * 0.92, 0.8, 0.0, 0.25)
        if beat >= 16:
            s.n(beat, 'glock', midi(nm) + 12, d, 0.35, -0.3, 0.3)
    for b in range(8):
        for i in range(8):
            c = chord_at(b * 4 + i * 0.5)
            s.n(b * 4 + i * 0.5, 'mando', c.v[(0, 1, 2, 1)[i % 4] % len(c.v)] + 12, 0.45,
                0.4 if i % 2 == 0 else 0.3, 0.45, 0.2)

    s = st.sec('stop', 8)
    travis(s, 0.9)
    folk_pad(s, 0.35)
    for start, dur, c in segments(P, 8):
        s.n(start, 'bass', c.bass, dur - 0.3, 0.55, 0.0, 0.0)
    for b in range(0, 8, 2):
        c = chord_at(b * 4)
        s.n(b * 4, 'glock', c.v[-1] + 12, 1.0, 0.3, -0.3, 0.4)

    s = st.sec('riser', 1, loop=False, tail_s=0.6, anchor_beats=4)
    s.n(0, 'revcrash', None, 4, 0.35, 0.0, 0.15, raw=True)
    for k, v in ((0, 0.5), (1, 0.6), (2, 0.7), (2.5, 0.75), (3, 0.85)):
        s.n(k, 'stomp', None, 0.5, v, 0.0, 0.15, raw=True)
    for k in (1, 3, 3.5):
        s.n(k, 'clap', None, 0.5, 0.7, 0.0, 0.25, raw=True)
    for i in range(16):
        s.n(i * 0.25, 'tamb', None, 0.25, 0.1 + 0.03 * i, 0.3, 0.1, raw=True)

    s = st.sec('hit_big', 1, loop=False, tail_s=3.0)
    s.n(0, 'stomp', None, 1, 1.0, 0.0, 0.2, raw=True)
    for pan in (-0.4, 0.0, 0.4):
        s.n(0, 'clap', None, 1, 0.75, pan, 0.3, raw=True)
    s.n(0, 'tamb', None, 1, 0.7, 0.3, 0.15, raw=True)
    s.n(0, 'crash', None, 4, 0.35, -0.1, 0.3, raw=True)

    s = st.sec('hit_soft', 1, loop=False, tail_s=2.5)
    s.gliss(0, 'glock', chord('G5 A5 B5 D6 E6'), 0.04, 0.45)

    s = st.sec('outro', 2, loop=False, tail_s=4.0)
    s.strum(0, 'steel', chord('G2 B2 D3 G3 B3 G4'), 8, 0.85, spread_s=0.025, pan=0.2, send=0.25)
    s.n(0, 'stomp', None, 1, 0.9, 0.0, 0.2, raw=True)
    s.n(0, 'clap', None, 1, 0.6, 0.0, 0.3, raw=True)
    for i, p in enumerate(chord('G5 B5 D6 G6')):
        s.n(1 + i * 0.5, 'glock', p, 1.0, 0.4, -0.3, 0.4, raw=True)
    s.n(0, 'bass', midi('G1'), 6, 0.7, 0.0, 0.0, raw=True)
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
    n, total = len(sig), len(dl)
    if circular:
        pos, j0 = 0, start % total
        while pos < n:
            m = min(n - pos, total - j0)
            for k in range(m):
                v = sig[pos + k]
                j = j0 + k
                dl[j] += v * gl
                dr[j] += v * gr
                ds[j] += v * gs
            pos += m
            j0 = 0
    else:
        k0 = max(0, -start)
        for k in range(k0, min(n, total - start)):
            v = sig[k]
            j = start + k
            dl[j] += v * gl
            dr[j] += v * gr
            ds[j] += v * gs


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


def render_style(name, out_root):
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


def _fail(msg):
    print(f'kamome-music: {msg}', file=sys.stderr)
    sys.exit(2)


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
    for ch in (L, R):
        for j in range(n):
            x = ch[j]
            a = abs(x)
            if a > 0.85:
                ch[j] = math.copysign(0.85 + 0.15 * math.tanh((a - 0.85) / 0.15), x)
    return L[:dur_n], R[:dur_n], cues


# ---------------------------------------------------------------- command line

def _default_out():
    return os.path.join(os.path.expanduser('~'), 'Kamome-music')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render', help='render loop sets')
    r.add_argument('--style', choices=STYLES, action='append')
    r.add_argument('--out', default=_default_out())
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

    if args.cmd == 'render':
        names = args.style or list(STYLES)
        with Pool(min(len(names), os.cpu_count() or 1)) as pool:
            for name, out, levels in pool.starmap(render_style, [(nm, args.out) for nm in names]):
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
