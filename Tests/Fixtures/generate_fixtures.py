#!/usr/bin/env python3
"""Deterministic synthetic GPX fixture generator for Kamome Phase 0 (spec §7).

Regenerate with:  python3 Tests/Fixtures/generate_fixtures.py
Paths are synthetic straight-line interpolations between anchor coordinates
with Gaussian GPS noise — NOT road-matched. Phase 1 gates count stops and
segments, not geometry fidelity. Each fixture's parameters are documented in
its own file header comment.
"""

import math
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

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

    clock = datetime(2026, 2, 10, 0, 30, tzinfo=timezone.utc)  # 08:30 AWST
    clock = t.leg(perth, mandurah, 90, 5, clock)
    clock = t.dwell(mandurah, 25, clock)                       # STOP 1
    clock = t.leg(mandurah, bunbury, 90, 5, clock)
    clock = t.dwell(bunbury, 25, clock)                        # STOP 2
    clock = t.walk_loop(bunbury, 25, 4.5, clock)               # WALK LOOP 1
    clock = t.dwell(bunbury, 0.5, clock)                       # brief return to car (< dwell window)
    clock = t.leg(bunbury, busselton, 85, 5, clock)
    clock = t.dwell(busselton, 20, clock)                      # STOP 3
    clock = t.walk_loop(busselton, 30, 4.0, clock, radius_m=400)  # WALK LOOP 2 (jetty)
    clock = t.dwell(busselton, 0.5, clock)
    clock = t.leg(busselton, margaret_river, 85, 5, clock)
    t.dwell(margaret_river, 30, clock)                         # STOP 4

    t.write("perth_margaret_river_day1.gpx", [
        "SYNTHETIC fixture (spec §7): Perth -> Mandurah -> Bunbury -> Busselton -> Margaret River.",
        "Generated by generate_fixtures.py, seed=1. Straight-line legs, NOT road-matched.",
        "~242 km straight-line (~280 km nominal by road), 2026-02-10, starts 08:30 AWST.",
        "Drive legs at 85-90 km/h sampled every 5 s; GPS noise sigma 4 m.",
        "Exactly 4 stops (dwell >= 180 s within 80 m): Mandurah 25 min, Bunbury 25 min,",
        "Busselton 20 min, Margaret River 30 min. Dwell sampled every 30 s, jitter 10 m.",
        "2 walk loops (4-4.5 km/h, 10 s sampling, sharp departure/return): Bunbury 25 min,",
        "Busselton jetty 30 min; each followed by a 30-s pause at the car (short enough",
        "that the 180 s containment window never fills -> no extra stop).",
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
