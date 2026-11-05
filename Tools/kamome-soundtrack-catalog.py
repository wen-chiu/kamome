#!/usr/bin/env python3
"""Master, encode and beatmap a folder of kept takes into the app's soundtrack catalog.

    ~/Kamome-music/.beatmap-venv/bin/python Tools/kamome-soundtrack-catalog.py \\
        ~/Kamome-music/acestep --engine acestep-1.5 --work ~/Kamome-music/catalog-run

Docs/handoff-music-in-the-film.md §4.3, §5. Desk only (ffmpeg, afconvert and the
beatmap venv's librosa); never run by the app or ./check.sh. For each
`<style>/<style>-<mood>-s<seed>.wav` under the folder:

  1. Master: ffmpeg `loudnorm`, two passes, to `target_lufs` with the true peak
     held a margin under `true_peak_max_dbtp` (AAC overshoots a little).
  2. Encode: afconvert, AAC VBR in an .m4a around `--bitrate` (Apple's encoder
     writes the priming the app's AVAudioFile trims). VBR, because at 128 kbps
     CBR the encoder's own overshoot took a master at −2.3 dBTP to −0.6 dBTP
     (measured 2026-11-03, anthem-depart-s1855554642); VBR held it at −1.2.
  3. Measure what ships: the .m4a is decoded back and `Tools/kamome-beatmap.py`
     runs on that decode, so the manifest's loudness, peak and duration are the
     shipped file's, not the master's.
  4. A take the beatmap tool refuses is left out and listed, never forced in.

Writes `<id>.m4a` and `<id>.json` into App/Resources/Soundtracks/ and lists the
kept ids, sorted, in `SoundtrackCatalog.json` beside them. Sections stay
`sections_confirmed: false` until Chiu has listened. No trip data: a track is
not a trip.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kamome_soundtrack_manifest as manifests  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, 'App', 'Resources', 'Soundtracks')
CATALOG = 'SoundtrackCatalog.json'
NAME = re.compile(r'^(?P<style>[a-z]+)-(?P<mood>[a-z]+)-s(?P<seed>\d+)$')


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def loudnorm_pass1(wav, target, peak):
    out = run(['ffmpeg', '-hide_banner', '-nostats', '-i', wav, '-af',
               f'loudnorm=I={target}:TP={peak}:LRA=20:print_format=json', '-f', 'null', '-']).stderr
    return json.loads(out[out.rfind('{'):out.rfind('}') + 1])


def master(wav, dest, target, peak):
    m = loudnorm_pass1(wav, target, peak)
    chain = (f'loudnorm=I={target}:TP={peak}:LRA=20:linear=true:measured_I={m["input_i"]}:'
             f'measured_TP={m["input_tp"]}:measured_LRA={m["input_lra"]}:measured_thresh={m["input_thresh"]}:'
             f'offset={m["target_offset"]}')
    result = run(['ffmpeg', '-hide_banner', '-nostats', '-y', '-i', wav, '-af', chain,
                  '-ar', '48000', '-c:a', 'pcm_s24le', dest])
    if result.returncode:
        raise RuntimeError(result.stderr[-400:])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('takes', help='folder holding <style>/<style>-<mood>-s<seed>.wav')
    ap.add_argument('--engine', required=True)
    ap.add_argument('--commit', help='engine commit; defaults to the folder manifest.json\'s')
    ap.add_argument('--work', required=True, help='scratch folder for masters and decodes')
    ap.add_argument('--bitrate', type=int, default=128000, help='AAC VBR target, bits per second (handoff §4.3: 128 kbps)')
    ap.add_argument('--peak-margin-db', type=float, default=0.5,
                    help='how far under the ceiling to master, for AAC overshoot')
    args = ap.parse_args()

    limit = manifests.limits()
    commit = args.commit
    folder_manifest = os.path.join(args.takes, 'manifest.json')
    if commit is None and os.path.exists(folder_manifest):
        commits = {t.get('ace_step_commit') for t in json.load(open(folder_manifest))}
        commit = commits.pop()[:7] if len(commits) == 1 else None
    os.makedirs(args.work, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)

    kept, refused = [], []
    for wav in sorted(glob.glob(os.path.join(args.takes, '*', '*.wav'))):
        track_id = os.path.splitext(os.path.basename(wav))[0]
        name = NAME.match(track_id)
        if not name:
            refused.append((track_id, 'name is not <style>-<mood>-s<seed>'))
            continue
        mastered = os.path.join(args.work, track_id + '.master.wav')
        m4a = os.path.join(args.work, track_id + '.m4a')
        decoded_dir = os.path.join(args.work, 'decoded')
        os.makedirs(decoded_dir, exist_ok=True)
        decoded = os.path.join(decoded_dir, track_id + '.wav')
        manifest = os.path.join(args.work, track_id + '.json')
        why = None
        for margin in (args.peak_margin_db, args.peak_margin_db + 1.0, args.peak_margin_db + 2.0):
            master(wav, mastered, limit['target_lufs'], limit['true_peak_max_dbtp'] - margin)
            for cmd in (['afconvert', '-f', 'm4af', '-d', 'aac', '-s', '3', '-b', str(args.bitrate), '-q', '127',
                         mastered, m4a],
                        ['afconvert', '-f', 'WAVE', '-d', 'LEI24', m4a, decoded]):
                result = run(cmd)
                if result.returncode:
                    raise RuntimeError(result.stderr[-400:])
            beatmap = run([sys.executable, os.path.join(REPO, 'Tools', 'kamome-beatmap.py'), decoded,
                           '--style', name['style'], '--mood', name['mood'], '--engine', args.engine,
                           *(['--commit', commit] if commit else []), '--out', manifest])
            if beatmap.returncode == 0:
                why = None
                break
            why = (beatmap.stderr.strip() or beatmap.stdout.strip()).splitlines()[-1]
            if 'true peak' not in why:
                break
        if why:
            refused.append((track_id, why))
            print(f'REFUSED {track_id}: {why}', flush=True)
            continue
        os.replace(m4a, os.path.join(OUT, track_id + '.m4a'))
        os.replace(manifest, os.path.join(OUT, track_id + '.json'))
        kept.append(track_id)
        print(f'kept    {track_id}: {beatmap.stdout.splitlines()[0]}', flush=True)

    with open(os.path.join(OUT, CATALOG), 'w') as f:
        json.dump({'schema_version': 1, 'tracks': sorted(kept)}, f, indent=2)
        f.write('\n')
    print(f'\n{len(kept)} kept, {len(refused)} refused')
    for track_id, why in refused:
        print(f'  {track_id}: {why}')


if __name__ == '__main__':
    main()
