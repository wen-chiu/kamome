"""The soundtrack manifest's rules, on the desk side. Stdlib only.

The schema is Core/ExportEngine/SoundtrackManifest.swift; this module refuses
exactly what its `validate(limits:)` refuses, in the same order and with the
same codes, so a fixture's expected refusal is written once and checked on both
sides (Tests/Fixtures/soundtracks/invalid/, SoundtrackManifestTests).

Used by Tools/kamome-beatmap.py before it writes a manifest, and by
Scripts/check-soundtrack-manifests.sh on every committed one. The loudness and
tempo limits are read from Config/TrackingConfig.json's `soundtrack` block, the
same numbers the app reads (CLAUDE.md rule 7).
"""
import json
import math
import os

SCHEMA_VERSION = 1
ROLES = ('intro', 'body', 'lift', 'peak', 'outro')
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# One sample at 8 kHz: float slack on bar-line arithmetic, not a choice.
# Mirrors SoundtrackManifest.fitSlackS.
FIT_SLACK_S = 1.0 / 8000


def limits(config_path=os.path.join(REPO, 'Config', 'TrackingConfig.json')):
    with open(config_path) as f:
        block = json.load(f)['soundtrack']
    return {key: block[key] for key in
            ('target_lufs', 'loudness_tolerance_lu', 'true_peak_max_dbtp', 'tempo_drift_max_bpm')}


class Refused(Exception):
    def __init__(self, code, why):
        super().__init__(f'{code}: {why}')
        self.code = code


def _number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def decode(manifest):
    """The shape Swift's Codable demands: every key present, every type right."""
    required = {
        'schema_version': int, 'id': str, 'style': str, 'mood': str, 'file': str,
        'duration_s': float, 'bpm': float, 'beats_per_bar': int, 'first_downbeat_s': float,
        'tempo_drift_bpm': float, 'sections': list, 'sections_confirmed': bool,
        'final_hit_bar': int, 'tail_s': float, 'integrated_lufs': float, 'true_peak_dbtp': float,
        'provenance': dict,
    }
    for key, kind in required.items():
        value = manifest.get(key)
        ok = (_number(value) if kind is float
              else isinstance(value, int) and not isinstance(value, bool) if kind is int
              else isinstance(value, kind))
        if not ok:
            raise Refused('decode', f'{key} is missing or not a {kind.__name__}')
    for section in manifest['sections']:
        for key, kind in (('name', str), ('start_bar', int), ('bars', int), ('energy', int), ('role', str)):
            if not isinstance(section.get(key), kind) or isinstance(section.get(key), bool) and kind is int:
                raise Refused('decode', f'a section has no {key}')
        if section['role'] not in ROLES:
            raise Refused('decode', f'unknown role {section["role"]}')
        if not isinstance(section.get('repeatable', False), bool):
            raise Refused('decode', 'repeatable must be true or false')
    provenance = manifest['provenance']
    if not isinstance(provenance.get('engine'), str):
        raise Refused('decode', 'provenance names no engine')
    if provenance.get('commit') is not None and not isinstance(provenance['commit'], str):
        raise Refused('decode', 'provenance commit must be text')
    seed = provenance.get('seed')
    if seed is not None and (not isinstance(seed, int) or isinstance(seed, bool)):
        raise Refused('decode', 'provenance seed must be a whole number')


def validate(manifest, limit):
    """Raises Refused with the first rule broken, in SoundtrackManifest's order."""
    decode(manifest)
    m = manifest
    sid = m['id']
    if m['schema_version'] != SCHEMA_VERSION:
        raise Refused('schema_version', f'{sid}: schema {m["schema_version"]}')
    if not all(m[k] for k in ('id', 'style', 'mood', 'file')):
        raise Refused('identity', f'{sid}: id, style, mood and file must all be named')
    if not (m['bpm'] > 0 and m['beats_per_bar'] >= 1 and m['first_downbeat_s'] >= 0 and m['duration_s'] > 0):
        raise Refused('grid', f'{sid}: bpm, beats per bar, first downbeat and duration must be positive')
    bar_s = 60.0 / m['bpm'] * m['beats_per_bar']

    def time_s(bar):
        return m['first_downbeat_s'] + bar * bar_s

    sections = m['sections']
    if not sections:
        raise Refused('sections_empty', f'{sid}: no sections')
    for s in sections:
        if s['bars'] < 1 or s['start_bar'] < 0 or s['energy'] < 1:
            raise Refused('section_shape', f'{sid}: {s["name"]} needs a start >= 0, bars >= 1 and energy >= 1')
    for prev, nxt in zip(sections, sections[1:]):
        if nxt['start_bar'] < prev['start_bar'] + prev['bars']:
            raise Refused('section_overlap', f'{sid}: {nxt["name"]} starts inside {prev["name"]}')
    last = sections[-1]
    if time_s(last['start_bar'] + last['bars']) > m['duration_s'] + FIT_SLACK_S:
        raise Refused('section_past_end', f'{sid}: {last["name"]} ends after the file does')
    if not any(s.get('repeatable', False) and s['role'] in ('body', 'peak') for s in sections):
        raise Refused('no_repeatable', f'{sid}: no repeatable body or peak section')

    outros = [s for s in sections if s['role'] == 'outro']
    if len(outros) != 1 or last['role'] != 'outro':
        raise Refused('outro', f'{sid}: exactly one outro, and it must be the last section')
    if not last['start_bar'] <= m['final_hit_bar'] <= last['start_bar'] + last['bars']:
        raise Refused('final_hit', f'{sid}: the final hit is not inside the outro')
    if not (m['tail_s'] >= 0 and time_s(m['final_hit_bar']) + m['tail_s'] <= m['duration_s'] + FIT_SLACK_S):
        raise Refused('tail', f'{sid}: the final hit and its tail run past the file')

    if abs(m['integrated_lufs'] - limit['target_lufs']) > limit['loudness_tolerance_lu']:
        raise Refused('loudness', f'{sid}: {m["integrated_lufs"]} LUFS, target {limit["target_lufs"]}')
    if m['true_peak_dbtp'] > limit['true_peak_max_dbtp']:
        raise Refused('true_peak', f'{sid}: true peak {m["true_peak_dbtp"]} dBTP')
    if not 0 <= m['tempo_drift_bpm'] <= limit['tempo_drift_max_bpm']:
        raise Refused('tempo_drift', f'{sid}: tempo drifts {m["tempo_drift_bpm"]} BPM')
