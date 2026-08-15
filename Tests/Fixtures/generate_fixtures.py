#!/usr/bin/env python3
"""Deterministic synthetic GPX fixture generator for Kamome Phase 0 (spec §7).

Regenerate with:  python3 Tests/Fixtures/generate_fixtures.py
Dwells and walk loops are synthetic geometry with Gaussian GPS noise. Drive
legs come in two flavors:

- `Track.leg` — straight-line interpolation between anchors, NOT road-matched.
  Phase 1 gates count stops and segments, not geometry fidelity.
- `Track.route_leg` — road-following geometry from the local OSRM server
  (`Docs/osrm-setup.md`), resampled to the requested speed/interval, same
  noise model. Added for P3.5 §1: validating §4.4 map matching end-to-end
  needs drive traces that are plausible GPS recordings of a real road trip —
  the straight-line legs sit kilometers off-road (e.g. across Geographe Bay),
  which the matching confidence gate rejects by design. Regenerating the
  perth fixture therefore needs the WA extract server running; the checked-in
  file is the artifact, so CI never touches the network.

Each fixture's parameters are documented in its own file header comment.
"""

import json
import math
import os
import random
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

OSRM_URL = os.environ.get("KAMOME_OSRM_URL", "http://127.0.0.1:5001")

HERE = Path(__file__).parent
M_PER_DEG_LAT = 111_320.0


def offset(lat, lon, north_m, east_m):
    return (
        lat + north_m / M_PER_DEG_LAT,
        lon + east_m / (M_PER_DEG_LAT * math.cos(math.radians(lat))),
    )


def dist_m(a, b):
    dlat = (b[0] - a[0]) * M_PER_DEG_LAT
    dlon = (b[1] - a[1]) * M_PER_DEG_LAT * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlon)


class Track:
    def __init__(self, seed, noise_sigma_m):
        self.rng = random.Random(seed)
        self.noise = noise_sigma_m
        self.points = []  # (lat, lon, ele, datetime)

    def _emit(self, lat, lon, ele, t):
        lat, lon = offset(lat, lon, self.rng.gauss(0, self.noise), self.rng.gauss(0, self.noise))
        self.points.append((lat, lon, ele, t))

    def leg(self, start, end, speed_kmh, sample_s, t):
        """Straight-line leg from start to end; returns arrival time."""
        total = dist_m(start, end)
        duration = total / (speed_kmh / 3.6)
        steps = max(1, int(duration // sample_s))
        for i in range(steps + 1):
            f = i / steps
            lat = start[0] + (end[0] - start[0]) * f
            lon = start[1] + (end[1] - start[1]) * f
            self._emit(lat, lon, 30, t + timedelta(seconds=duration * f))
        return t + timedelta(seconds=duration)

    def route_leg(self, start, end, speed_kmh, sample_s, t):
        """Road-following leg: OSRM /route geometry between the anchors,
        resampled to one point per sample_s at speed_kmh; returns arrival
        time. Needs the local server (Docs/osrm-setup.md)."""
        url = (f"{OSRM_URL}/route/v1/driving/"
               f"{start[1]:.6f},{start[0]:.6f};{end[1]:.6f},{end[0]:.6f}"
               f"?geometries=geojson&overview=full")
        try:
            body = json.load(urllib.request.urlopen(url))
        except OSError as error:
            raise SystemExit(
                f"OSRM route request failed ({error}) — road-matched legs need the "
                f"local server from Docs/osrm-setup.md at {OSRM_URL} "
                "(override with KAMOME_OSRM_URL)"
            )
        shape = [(lat, lon) for lon, lat in body["routes"][0]["geometry"]["coordinates"]]

        mps = speed_kmh / 3.6
        step_m = mps * sample_s
        self._emit(*start, 30, t)
        walked = 0.0
        next_emit = step_m
        for a, b in zip(shape, shape[1:]):
            seg = dist_m(a, b)
            if seg == 0:
                continue
            while next_emit <= walked + seg:
                f = (next_emit - walked) / seg
                lat = a[0] + (b[0] - a[0]) * f
                lon = a[1] + (b[1] - a[1]) * f
                self._emit(lat, lon, 30, t + timedelta(seconds=next_emit / mps))
                next_emit += step_m
            walked += seg
        duration = walked / mps
        self._emit(*end, 30, t + timedelta(seconds=duration))
        return t + timedelta(seconds=duration)

    def dwell(self, center, minutes, t, sample_s=30, jitter_m=10):
        end = t + timedelta(minutes=minutes)
        cur = t
        while cur <= end:
            lat, lon = offset(center[0], center[1],
                              self.rng.gauss(0, jitter_m), self.rng.gauss(0, jitter_m))
            self._emit(lat, lon, 30, cur)
            cur += timedelta(seconds=sample_s)
        return end

    def walk_loop(self, center, minutes, speed_kmh, t, radius_m=250, sample_s=10):
        """Closed loop on a circle around center; starts and ends at center.
        Departure/return are deliberately sharp (factor 12): a slow creeping
        return + pause would legitimately satisfy the §4.2 containment rule
        and read as an extra stop."""
        circumference = minutes * 60 * speed_kmh / 3.6
        end = t + timedelta(minutes=minutes)
        cur, elapsed_total = t, minutes * 60
        while cur <= end:
            f = (cur - t).total_seconds() / elapsed_total
            # out to the circle, around it, and back
            r = radius_m * min(1.0, min(f, 1 - f) * 12)
            ang = f * circumference / max(radius_m, 1)
            lat, lon = offset(center[0], center[1], r * math.cos(ang), r * math.sin(ang))
            self._emit(lat, lon, 30, cur)
            cur += timedelta(seconds=sample_s)
        return end

    def write(self, name, header_lines):
        header = "\n".join("  " + line for line in header_lines)
        pts = []
        for lat, lon, ele, t in self.points:
            stamp = t.strftime("%Y-%m-%dT%H:%M:%SZ")
            pts.append(
                f'      <trkpt lat="{lat:.6f}" lon="{lon:.6f}">'
                f"<ele>{ele:.0f}</ele><time>{stamp}</time></trkpt>"
            )
        body = "\n".join(pts)
        (HERE / name).write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<!--
{header}
-->
<gpx version="1.1" creator="kamome-fixture-generator" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>{name.removesuffix('.gpx')}</name>
    <trkseg>
{body}
    </trkseg>
  </trk>
</gpx>
""")
        print(f"{name}: {len(self.points)} points")


def perth_margaret_river():
    t = Track(seed=1, noise_sigma_m=4)
    perth = (-31.9530, 115.8570)
    mandurah = (-32.5290, 115.7220)
    bunbury = (-33.3270, 115.6410)
    busselton = (-33.6440, 115.3450)
    margaret_river = (-33.9550, 115.0750)

    # Parked dwells use jitter_m=4: iid jitter sigma 10 m at 30 s sampling
    # averages ~2.1 km/h of pseudo-motion — right on the knife-edge between
    # speed_stationary_max_kmh (1.5) and walking, so whether a dwell
    # live-pauses or melts into a walk segment used to depend on the rng
    # draw. Sigma 4 (~1.1 km/h) is decisively stationary. The Bunbury and
    # Busselton visits are decisively the *other* thing — the whole visit
    # is an on-foot loop from the car (walk-visit stop, ADR 2026-07-18) —
    # so the fixture's 2 dwells + 2 walk visits are structural, not luck.
    clock = datetime(2026, 2, 10, 0, 30, tzinfo=timezone.utc)  # 08:30 AWST
    clock = t.route_leg(perth, mandurah, 90, 5, clock)
    clock = t.dwell(mandurah, 25, clock, jitter_m=4)           # STOP 1 (parked)
    clock = t.route_leg(mandurah, bunbury, 90, 5, clock)
    clock = t.walk_loop(bunbury, 50, 4.5, clock)               # STOP 2 (walk visit)
    clock = t.dwell(bunbury, 0.5, clock, jitter_m=4)           # brief return to car (< dwell window)
    clock = t.route_leg(bunbury, busselton, 85, 5, clock)
    clock = t.walk_loop(busselton, 50, 4.0, clock, radius_m=400)  # STOP 3 (jetty walk visit)
    clock = t.dwell(busselton, 0.5, clock, jitter_m=4)
    clock = t.route_leg(busselton, margaret_river, 85, 5, clock)
    t.dwell(margaret_river, 30, clock, jitter_m=4)             # STOP 4 (parked)

    t.write("perth_margaret_river_day1.gpx", [
        "SYNTHETIC fixture (spec §7): Perth -> Mandurah -> Bunbury -> Busselton -> Margaret River.",
        "Generated by generate_fixtures.py, seed=1.",
        "Drive legs are ROAD-MATCHED (P3.5 §1, 2026-07-19): geometry from the local OSRM",
        "WA-extract server (Docs/osrm-setup.md), so the trace is a plausible GPS recording",
        "a §4.4 /match can confidently snap. Earlier revisions used straight anchor-to-anchor",
        "lines (km off-road, e.g. across Geographe Bay), which the confidence gate rejects.",
        "2026-02-10, starts 08:30 AWST.",
        "Drive legs at 85-90 km/h sampled every 5 s; GPS noise sigma 4 m.",
        "Exactly 4 stops, decisively shaped (not rng-marginal — see generator comment):",
        "- Mandurah 25 min + Margaret River 30 min: parked dwells, 30 s sampling,",
        "  jitter 4 m (~1.1 km/h, below the 1.5 km/h stationary ceiling -> live pause).",
        "- Bunbury 50 min + Busselton jetty 50 min: on-foot loop visits from the car",
        "  (4-4.5 km/h, 10 s sampling, sharp departure/return) -> derived walk-visit",
        "  stops; each followed by a 30-s pause at the car (short enough that the",
        "  180 s containment window never fills -> no extra stop).",
        "Phase 1 gate: exactly 4 stops, >= 2 drive segments, >= 2 walk segments.",
    ])


def taiwan_huandao():
    t = Track(seed=2, noise_sigma_m=5)
    days = [
        # (start, mid-stop, end, mode, speed_kmh)
        ((25.0330, 121.5654), (24.8138, 120.9675), (24.1477, 120.6736), "car", 80),      # D1 Taipei->Taichung
        ((24.1477, 120.6736), (23.4800, 120.4490), (22.9999, 120.2270), "car", 80),      # D2 ->Tainan
        ((22.9999, 120.2270), (22.6273, 120.3014), (22.4713, 120.4491), "car", 75),      # D3 ->Donggang
        ((22.4713, 120.4491), (22.0040, 120.7440), (21.9480, 120.7790), "car", 70),      # D4 ->Kenting
        ((21.9480, 120.7790), (22.0870, 120.9020), (22.3660, 120.9010), "scooter", 45),  # D5 ->Dawu
        ((22.3660, 120.9010), (22.6120, 121.0230), (22.7583, 121.1444), "scooter", 45),  # D6 ->Taitung
        ((22.7583, 121.1444), (23.0990, 121.3650), (23.9910, 121.6114), "rail", 140),    # D7 ->Hualien (TRA)
        ((23.9910, 121.6114), (24.4680, 121.7580), (24.7570, 121.7530), "scooter", 45),  # D8 ->Yilan
        ((24.7570, 121.7530), (24.9370, 121.6650), (25.0330, 121.5654), "car", 70),      # D9 ->Taipei (loop closed)
    ]
    for day_idx, (start, mid, end, mode, speed) in enumerate(days):
        clock = datetime(2026, 4, 1, 1, 0, tzinfo=timezone.utc) + timedelta(days=day_idx)
        sample = 15 if mode != "rail" else 10
        clock = t.leg(start, mid, speed, sample, clock)
        if mode != "rail":
            clock = t.dwell(mid, 30, clock, sample_s=60)
        clock = t.leg(mid, end, speed, sample, clock)
        t.dwell(end, 30, clock, sample_s=60)

    t.write("taiwan_huandao_9days.gpx", [
        "SYNTHETIC fixture (spec §7): 9-day Taiwan round-island (huandao) loop, clockwise",
        "from Taipei via west coast, Kenting, east coast, back to Taipei. Loop closes on",
        "day 9 (exercises Phase 4 huandao detection). Generated by generate_fixtures.py,",
        "seed=2. Straight-line legs, NOT road-matched. GPS noise sigma 5 m.",
        "Modes: D1-D4 car 70-80 km/h, D5/D6/D8 scooter 45 km/h,",
        "D7 Taitung->Hualien rail at sustained 140 km/h — deliberately faster than real",
        "TRA so the >130 km/h transit heuristic (spec §1.7) fires.",
        "Each day: leg, 30-min mid stop (except rail day), leg, 30-min arrival stop;",
        "overnight gaps between days. Drive/scooter sampled 15 s, rail 10 s, dwells 60 s.",
    ])


def city_walk_flapping():
    t = Track(seed=3, noise_sigma_m=12)
    rng = random.Random(30)
    start = (25.0330, 121.5430)  # Da'an, Taipei
    clock = datetime(2026, 3, 15, 6, 0, tzinfo=timezone.utc)
    cur = start
    heading = 0.0
    end_time = clock + timedelta(minutes=50)
    next_burst = clock + timedelta(minutes=6)
    next_pause = clock + timedelta(minutes=4)
    while clock < end_time:
        if clock >= next_burst:
            # short fast burst (bus hop / jog): 30-45 s at 18-22 km/h,
            # below mode_confirm_s=60 so it must NOT confirm a drive segment
            secs = rng.uniform(30, 45)
            speed = rng.uniform(18, 22)
            target = offset(cur[0], cur[1],
                            speed / 3.6 * secs * math.cos(heading),
                            speed / 3.6 * secs * math.sin(heading))
            clock = t.leg(cur, target, speed, 5, clock)
            cur = target
            next_burst = clock + timedelta(minutes=rng.uniform(5, 7))
        elif clock >= next_pause:
            # traffic-light pause 30-45 s. Kept short: a longer pause plus the
            # adjacent walking can legitimately satisfy §4.2's contained-
            # within-80m rule, which would (correctly) be a stop — this
            # fixture models a walker who keeps moving.
            clock = t.dwell(cur, rng.uniform(0.5, 0.75), clock, sample_s=10, jitter_m=8)
            next_pause = clock + timedelta(minutes=rng.uniform(3, 5))
        else:
            # brisk city walking, mostly straight blocks
            heading += rng.uniform(-0.15, 0.15)
            secs = 60
            target = offset(cur[0], cur[1],
                            5.2 / 3.6 * secs * math.cos(heading),
                            5.2 / 3.6 * secs * math.sin(heading))
            clock = t.leg(cur, target, 5.2, 5, clock)
            cur = target

    t.write("city_walk_flapping.gpx", [
        "SYNTHETIC fixture (spec §7): 50-min urban walk torture test, Da'an Taipei.",
        "Generated by generate_fixtures.py, seed=3/30. Mostly-straight blocks",
        "(heading wander ±0.15 rad/min), 5 s sampling, heavy urban GPS noise sigma 12 m.",
        "Base walking 5.2 km/h with mode-flapping traps:",
        "- every ~5-7 min a 30-45 s burst at 18-22 km/h (< mode_confirm_s=60 -> must not",
        "  confirm a new segment)",
        "- every ~3-5 min a 30-45 s traffic-light pause (short + brisk walking keeps the",
        "  180 s window from ever being contained in 80 m -> no stop)",
        "Phase 1 gate: <= 1 spurious segment when replayed through the engine.",
    ])


if __name__ == "__main__":
    perth_margaret_river()
    taiwan_huandao()
    city_walk_flapping()
