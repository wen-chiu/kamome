#!/usr/bin/env python3
"""Centre a vehicle sprite set's content in a uniform square canvas.

Why this exists (2026-08-16). The renderer places the **canvas** centre at the
vehicle's position and scales by canvas rather than by content bounds — see
`Core/ExportEngine/Resources/Vehicles/README.md`. So two properties have to hold
across a set, and neither is something an image generator will give you reliably:

1. **Every drawing shares one canvas size.** Otherwise the subject pulses as it
   turns, because the same `subject_length_px` maps onto different canvases.
2. **Every drawing's content sits at the canvas centre.** Otherwise the subject
   jumps sideways relative to the route as it turns, by the difference between
   each drawing's own offset.

Measured before this tool existed: `car-red` (hand-corrected, approved) varied
10.2% of its canvas across the eight; a generated `plane` set varied 22.9% and
had content running off the canvas edge. Correcting that by prompt is luck;
correcting it here makes it an invariant.

**What this does NOT do: rescale content.** A car seen side-on really is longer
on screen than one seen from behind, and that variation is correct — the README
says so. Content is translated, never resized, so the set keeps its relative
proportions.

Pure stdlib: no PIL on this machine, so PNG decode/encode is done here. Handles
8-bit RGBA (colour type 6) only, which is what every sprite in the folder is.

    ./Tools/center-sprites.py Core/ExportEngine/Resources/Vehicles/scooter
    ./Tools/center-sprites.py --check Core/ExportEngine/Resources/Vehicles/*

`--check` reports without writing. Always run it first; the write is in place.
"""

import argparse
import glob
import math
import os
import struct
import sys
import zlib

ALPHA_FLOOR = 8          # below this an edge pixel is antialiasing, not content
DEFAULT_FILL = 0.74      # car-red's widest drawing fills 74% of its canvas
DIRECTIONS = ("n", "ne", "e", "se", "s", "sw", "w", "nw")


def decode(path):
    """→ (bytearray RGBA, width, height). Raises on anything not 8-bit RGBA."""
    data = open(path, "rb").read()
    idat, width, height, depth, colour = b"", None, None, None, None
    i = 8
    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        kind, body = data[i + 4:i + 8], data[i + 8:i + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
        elif kind == b"IDAT":
            idat += body
        i += 12 + length
    if (depth, colour) != (8, 6):
        raise ValueError(f"{path}: expected 8-bit RGBA, got depth={depth} colour={colour}")
    raw, stride, out, prev, p = zlib.decompress(idat), width * 4, bytearray(), bytearray(width * 4), 0

    def paeth(a, b, c):
        guess = a + b - c
        da, db, dc = abs(guess - a), abs(guess - b), abs(guess - c)
        return a if (da <= db and da <= dc) else (b if db <= dc else c)

    for _ in range(height):
        filt, row = raw[p], bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if filt:
            for x in range(stride):
                a = row[x - 4] if x >= 4 else 0
                b = prev[x]
                c = prev[x - 4] if x >= 4 else 0
                if filt == 1:
                    row[x] = (row[x] + a) & 255
                elif filt == 2:
                    row[x] = (row[x] + b) & 255
                elif filt == 3:
                    row[x] = (row[x] + (a + b) // 2) & 255
                elif filt == 4:
                    row[x] = (row[x] + paeth(a, b, c)) & 255
                else:
                    raise ValueError(f"{path}: unknown PNG filter {filt}")
        out += row
        prev = row
    return out, width, height


def encode(path, px, width, height):
    """Write 8-bit RGBA with filter 0 — sprites are small and this stays readable."""
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += px[y * stride:(y + 1) * stride]

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(out)


def content_box(px, width, height):
    """Tightest box holding pixels above ALPHA_FLOOR, or None if fully clear."""
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        base = y * width * 4
        for x in range(width):
            if px[base + x * 4 + 3] > ALPHA_FLOOR:
                min_x, max_x = min(min_x, x), max(max_x, x)
                min_y, max_y = min(min_y, y), max(max_y, y)
    return None if max_x < 0 else (min_x, min_y, max_x, max_y)


def recentre(px, width, height, box, canvas):
    """Content translated so its box centre lands on the canvas centre."""
    min_x, min_y, max_x, max_y = box
    out = bytearray(canvas * canvas * 4)
    dx = (canvas - (max_x - min_x + 1)) // 2 - min_x
    dy = (canvas - (max_y - min_y + 1)) // 2 - min_y
    for y in range(min_y, max_y + 1):
        ty = y + dy
        if not 0 <= ty < canvas:
            continue
        src = (y * width + min_x) * 4
        dst = (ty * canvas + min_x + dx) * 4
        out[dst:dst + (max_x - min_x + 1) * 4] = px[src:src + (max_x - min_x + 1) * 4]
    return out


def process(folder, fill, check):
    names = [d for d in DIRECTIONS if os.path.exists(os.path.join(folder, f"{d}.png"))]
    singles = [n for n in ("omni", "logo") if os.path.exists(os.path.join(folder, f"{n}.png"))]
    if not names and not singles:
        print(f"{folder}: nothing to do")
        return True
    if names and len(names) != len(DIRECTIONS):
        print(f"⚠️  {folder}: {len(names)} of 8 directions — a partial set never renders")

    loaded = {}
    for n in names + singles:
        path = os.path.join(folder, f"{n}.png")
        px, w, h = decode(path)
        box = content_box(px, w, h)
        if box is None:
            print(f"⚠️  {folder}/{n}.png: no content")
            return False
        loaded[n] = (px, w, h, box)

    # One canvas for the directional set, sized so its widest drawing fills
    # `fill` — matching car-red keeps every vehicle's apparent size comparable
    # at the same `subject_length_px`.
    report = []
    if names:
        widest = max(max(b[2] - b[0] + 1, b[3] - b[1] + 1) for _, _, _, b in
                     (loaded[n] for n in names))
        canvas = int(math.ceil(widest / fill / 2) * 2)
        for n in names:
            px, w, h, box = loaded[n]
            before = max(abs((box[0] + box[2]) / 2 - (w - 1) / 2),
                         abs((box[1] + box[3]) / 2 - (h - 1) / 2))
            report.append((n, w, h, canvas, before))
            if not check:
                encode(os.path.join(folder, f"{n}.png"),
                       recentre(px, w, h, box, canvas), canvas, canvas)

    # A thumbnail and an omni mark are each their own canvas — they are not part
    # of the set's scale relationship, they only need to be square and centred.
    for n in singles:
        px, w, h, box = loaded[n]
        widest = max(box[2] - box[0] + 1, box[3] - box[1] + 1)
        canvas = int(math.ceil(widest / fill / 2) * 2)
        before = max(abs((box[0] + box[2]) / 2 - (w - 1) / 2),
                     abs((box[1] + box[3]) / 2 - (h - 1) / 2))
        report.append((n, w, h, canvas, before))
        if not check:
            encode(os.path.join(folder, f"{n}.png"),
                   recentre(px, w, h, box, canvas), canvas, canvas)

    label = "would be" if check else "now"
    print(f"\n{folder}")
    for n, w, h, canvas, before in report:
        pct = before / max(w, h) * 100
        print(f"  {n + '.png':10} {w}x{h} → {canvas}x{canvas}   "
              f"offset was {before:5.1f}px ({pct:4.1f}% of canvas), {label} 0")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folders", nargs="+")
    ap.add_argument("--check", action="store_true", help="report without writing")
    ap.add_argument("--fill", type=float, default=DEFAULT_FILL,
                    help=f"fraction of canvas the widest drawing fills (default {DEFAULT_FILL})")
    args = ap.parse_args()
    ok = all(process(f.rstrip("/"), args.fill, args.check)
             for f in args.folders if os.path.isdir(f))
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
