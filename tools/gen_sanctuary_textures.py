#!/usr/bin/env python3
"""Generates the Sanctuary art (T-28, D-030): four 16x16 node tiles, the coin and two potion icons, and a spark.

Pure stdlib (zlib, struct, random), so it runs anywhere Python 3 does. Every pixel is drawn here; nothing is copied
from a game. Style: weathered stone, pale gold, warm light (lanterns and the altar glow).
Output: mods/minemon/minemon_sanctuary/textures/ (relative to the repo root). Deterministic: the same bytes each run.

Usage: python3 tools/gen_sanctuary_textures.py [output_dir]
"""

import math
import os
import random
import struct
import sys
import zlib

SIZE = 16
CENTRE = (SIZE - 1) / 2.0

STONE_RAMP = [(70, 66, 78), (88, 84, 96), (106, 101, 112), (124, 118, 128)]
GOLD = (222, 178, 88)
GOLD_DARK = (150, 104, 44)
GOLD_LIGHT = (255, 230, 160)
GLOW = (255, 206, 118)
GLASS = (206, 224, 234)
GLASS_EDGE = (58, 66, 78)
CORK = (150, 108, 66)
RED_LIQUID = (214, 62, 72)
BLUE_LIQUID = (66, 128, 230)
FRAME = (38, 34, 30)
TRANSPARENT = (0, 0, 0, 0)


def png_bytes(width, height, rows):
    """Encodes RGBA rows (lists of 4-tuples) as a PNG file."""

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type: none
        for px in row:
            raw.extend(px)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def opaque(rgb):
    return (rgb[0], rgb[1], rgb[2], 255)


def stone_grid(seed):
    """A 16x16 weathered stone field, lit from the top left, as RGB tuples."""
    rng = random.Random(seed)
    grid = [[0] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            grid[y][x] = rng.randint(0, 2)
    # Block seams: a darker line every 8 pixels, offset per row, like laid stone.
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            idx = grid[y][x]
            if y % 8 == 0 or (x + (4 if (y // 8) % 2 else 0)) % 8 == 0 and y % 8 < 4:
                idx = 0
            elif (x * 3 + y * 5) % 11 == 0:
                idx = 3
            light = 1 if x + y < SIZE else 0
            row.append(STONE_RAMP[min(3, idx + light)])
        rows.append(row)
    return rows


def paint(rows):
    return [[opaque(px) for px in row] for row in rows]


def altar():
    rows = stone_grid(101)
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - CENTRE, y - CENTRE)
            if 4.4 <= d <= 5.6:
                rows[y][x] = GOLD
            elif d < 2.2:
                rows[y][x] = GLOW
            elif d < 3.2:
                rows[y][x] = GOLD_LIGHT if (x + y) % 2 == 0 else GOLD_DARK
    return paint(rows)


def pc():
    rows = stone_grid(202)
    for y in range(SIZE):
        for x in range(SIZE):
            rows[y][x] = tuple(int(c * 0.8) for c in rows[y][x])
    for y in range(3, 10):
        for x in range(3, 13):
            rows[y][x] = (30, 62, 72)
    for y in range(3, 10):
        rows[y][3] = GOLD_DARK
        rows[y][12] = GOLD_DARK
    for x in range(3, 13):
        rows[3][x] = GOLD_DARK
        rows[9][x] = GOLD_DARK
    for x in range(4, 12, 2):
        rows[5][x] = GOLD_LIGHT
        rows[7][x + 1 if x + 1 < 12 else x] = GOLD
    for x in range(4, 12):
        rows[11][x] = GOLD if x % 3 else GOLD_DARK
    return paint(rows)


def counter():
    rows = stone_grid(303)
    for x in range(SIZE):
        rows[0][x] = GOLD
        rows[1][x] = GOLD_DARK
        rows[SIZE - 1][x] = GOLD_DARK
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - CENTRE, y - 9.5)
            if d < 1.6:
                rows[y][x] = GOLD_LIGHT
    return paint(rows)


def lantern():
    rows = [[FRAME] * SIZE for _ in range(SIZE)]
    for y in range(2, SIZE - 2):
        for x in range(2, SIZE - 2):
            if x in (2, SIZE - 3) or y in (2, SIZE - 3):
                rows[y][x] = FRAME
                continue
            d = math.hypot(x - CENTRE, y - CENTRE) / (SIZE / 2.0)
            t = min(1.0, d)
            r = int(GLOW[0] + (232 - GLOW[0]) * t)
            g = int(GLOW[1] + (150 - GLOW[1]) * t)
            b = int(GLOW[2] + (70 - GLOW[2]) * t)
            rows[y][x] = (r, g, b)
    for y in range(SIZE):
        for x in range(SIZE):
            if (x, y) in ((2, 2), (SIZE - 3, 2), (2, SIZE - 3), (SIZE - 3, SIZE - 3)):
                rows[y][x] = GOLD
    return paint(rows)


def coin():
    glyph = ["11110", "10001", "10001", "11110", "10000", "10000", "10000"]
    out = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            d = math.hypot(x - CENTRE, y - CENTRE)
            if d > 7.2:
                row.append(TRANSPARENT)
            elif d > 6.0:
                row.append(opaque(GOLD_DARK))
            else:
                gx, gy = x - 5, y - 4
                inside = 0 <= gx < 5 and 0 <= gy < 7 and glyph[gy][gx] == "1"
                if inside:
                    row.append(opaque(GOLD_DARK))
                elif y < 6 and d < 4.5:
                    row.append(opaque(GOLD_LIGHT))
                else:
                    row.append(opaque(GOLD))
        out.append(row)
    return out


def potion(liquid, cap):
    out = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            px = TRANSPARENT
            # Cork and neck.
            if 1 <= y <= 2 and 6 <= x <= 9:
                px = opaque(cap if y == 1 else CORK)
            elif 3 <= y <= 5 and 6 <= x <= 9:
                px = opaque(GLASS_EDGE) if x in (6, 9) else opaque(GLASS)
            # Round body.
            dx = (x - 7.5) / 5.6
            dy = (y - 10.5) / 4.8
            dist = dx * dx + dy * dy
            if y >= 6 and dist <= 1.0:
                if dist > 0.72:
                    px = opaque(GLASS_EDGE)
                elif y >= 9:
                    px = opaque(liquid)
                    if x in (4, 5) and y < 11:
                        px = opaque(GLASS_LIGHT_TINT)
                else:
                    px = opaque(GLASS)
            row.append(px)
        out.append(row)
    return out


GLASS_LIGHT_TINT = (255, 214, 214)


def spark():
    out = []
    for y in range(8):
        row = []
        for x in range(8):
            d = math.hypot(x - 3.5, y - 3.5)
            a = max(0.0, 1.0 - d / 4.0)
            row.append((GOLD_LIGHT[0], GOLD_LIGHT[1], GOLD_LIGHT[2], int(a * 255)))
        out.append(row)
    return out


def write(path, rows):
    height = len(rows)
    width = len(rows[0])
    with open(path, "wb") as f:
        f.write(png_bytes(width, height, rows))


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = argv[1] if len(argv) > 1 else os.path.join(here, "..", "mods", "minemon", "minemon_sanctuary",
                                                         "textures")
    os.makedirs(out_dir, exist_ok=True)
    files = {
        "minemon_sanctuary_altar.png": altar(),
        "minemon_sanctuary_pc.png": pc(),
        "minemon_sanctuary_counter.png": counter(),
        "minemon_sanctuary_lantern.png": lantern(),
        "minemon_sanctuary_coin.png": coin(),
        "minemon_sanctuary_potion.png": potion(RED_LIQUID, GOLD_DARK),
        "minemon_sanctuary_super_potion.png": potion(BLUE_LIQUID, GOLD),
        "minemon_sanctuary_spark.png": spark(),
    }
    for name in sorted(files):
        path = os.path.join(out_dir, name)
        write(path, files[name])
        print("wrote " + os.path.normpath(path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
