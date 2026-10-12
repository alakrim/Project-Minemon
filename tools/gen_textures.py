#!/usr/bin/env python3
"""Generate the Minemon block atlas (D-021). Dev-only tool, deterministic.

Writes:
  assets/textures/blocks_atlas.png   256x256 RGBA, 16x16 tiles of 16 px (index = row*16 + col)
  assets/textures/blocks_atlas.json  {"tile_size", "tiles", "tints"}
  builds/atlas_preview.png           labelled 6x sheet plus a 4x4 tiling preview

Art direction: every material uses a short hand-picked ramp. Shadows lean cool
(blue/purple), highlights lean warm (yellow), and light comes from the top-left.
Every texture wraps toroidally so it tiles without seams. Grass tops, leaves and
tall grass/fern are authored in a neutral green-grey range and are multiplied by
the biome tint at runtime (see the "tints" key).

Usage: python3 tools/gen_textures.py
"""

from __future__ import annotations

import json
import math
import os
import random
import zlib
from typing import Callable

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ATLAS_PNG = os.path.join(ROOT, "assets", "textures", "blocks_atlas.png")
ATLAS_JSON = os.path.join(ROOT, "assets", "textures", "blocks_atlas.json")
PREVIEW_PNG = os.path.join(ROOT, "builds", "atlas_preview.png")

TILE = 16
COLS = 16
ATLAS_SIZE = 256
SEED = 0x4D494E45  # "MINE"; mixed with a crc32 of each texture name
PREVIEW_SCALE = 6
TILING_SCALE = 4
BG = (43, 43, 48)

RGB = tuple[int, int, int]
RGBA = tuple[int, int, int, int]
Grid = list[list[RGBA]]
Idx = list[list[int]]

NAMES: list[str] = [
    "grass_top", "grass_side", "dirt", "stone", "cobblestone", "gravel", "sand",
    "sandstone_top", "sandstone_side", "clay", "snow", "grass_side_snowed",
    "log_oak_side", "log_oak_top", "planks_oak", "leaves_oak",
    "log_birch_side", "log_birch_top", "leaves_birch",
    "log_spruce_side", "log_spruce_top", "leaves_spruce",
    "water", "tall_grass", "fern", "flower_red", "flower_yellow", "flower_blue",
    "flower_white", "dead_bush", "mushroom_brown", "mushroom_red",
    "coal_ore", "iron_ore", "mossy_cobblestone",
]

TINTS: dict[str, dict[str, str]] = {
    "grass": {"plains": "#7fb04a", "forest": "#6a9e3f", "mountain": "#8aa86a", "beach": "#8fb85a"},
    "foliage": {"plains": "#6fa83e", "forest": "#5c9437", "mountain": "#7e9a5e", "beach": "#86b05a"},
}


# ---------------------------------------------------------------- colour helpers

def hx(h: str) -> RGB:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def ramp(*hexes: str) -> list[RGB]:
    return [hx(h) for h in hexes]


def clamp_channel(v: float) -> int:
    return int(round(max(14.0, min(244.0, v))))


def grade(rgb: RGB, strength: float = 1.0) -> RGB:
    """Hue-shift: shadows drift cool (blue/purple), highlights drift warm (yellow)."""
    r, g, b = rgb
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    cool = (1.0 - lum) * strength
    warm = lum * strength
    return (
        clamp_channel(r - 4.0 * cool + 5.0 * warm),
        clamp_channel(g - 1.5 * cool + 2.5 * warm),
        clamp_channel(b + 9.0 * cool - 6.0 * warm),
    )


def light_weight(dx: float, dy: float) -> float:
    """Fades lighting to zero near the far side of a site so the torus wrap never flips it."""
    return max(0.0, min(1.0, (8.0 - math.hypot(dx, dy)) / 3.0))


def clampi(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def rng_for(name: str) -> random.Random:
    return random.Random(SEED ^ zlib.crc32(name.encode("utf-8")))


# ---------------------------------------------------------------- noise and fields

def vnoise(rng: random.Random, cx: int, cy: int) -> list[list[float]]:
    """Toroidal value noise on a cx by cy lattice, smoothstep-interpolated over the 16 px tile."""
    lat = [[rng.random() for _ in range(cx)] for _ in range(cy)]
    out = [[0.0] * TILE for _ in range(TILE)]
    for y in range(TILE):
        fy = y * cy / TILE
        y0 = int(fy)
        ty = fy - y0
        ty = ty * ty * (3 - 2 * ty)
        ya, yb = y0 % cy, (y0 + 1) % cy
        for x in range(TILE):
            fx = x * cx / TILE
            x0 = int(fx)
            tx = fx - x0
            tx = tx * tx * (3 - 2 * tx)
            xa, xb = x0 % cx, (x0 + 1) % cx
            top = lat[ya][xa] + (lat[ya][xb] - lat[ya][xa]) * tx
            bot = lat[yb][xa] + (lat[yb][xb] - lat[yb][xa]) * tx
            out[y][x] = top + (bot - top) * ty
    return out


def normalize(field: list[list[float]]) -> list[list[float]]:
    flat = [v for row in field for v in row]
    lo, hi = min(flat), max(flat)
    span = (hi - lo) or 1.0
    return [[(v - lo) / span for v in row] for row in field]


def fbm(rng: random.Random, octaves: list[tuple[int, int, float]]) -> list[list[float]]:
    acc = [[0.0] * TILE for _ in range(TILE)]
    for cx, cy, w in octaves:
        n = vnoise(rng, cx, cy)
        for y in range(TILE):
            for x in range(TILE):
                acc[y][x] += n[y][x] * w
    return normalize(acc)


def bucket(v: float, n: int) -> int:
    return min(n - 1, int(v * n))


def top_mask(field: list[list[float]], fraction: float) -> list[list[bool]]:
    """Mark the highest `fraction` of pixels. Keeps holes clumped where the field is smooth."""
    count = int(round(fraction * TILE * TILE))
    order = sorted(range(TILE * TILE), key=lambda i: (field[i // TILE][i % TILE], i))
    mask = [[False] * TILE for _ in range(TILE)]
    for i in order[len(order) - count:]:
        mask[i // TILE][i % TILE] = True
    return mask


def blank_idx(v: int = 0) -> Idx:
    return [[v] * TILE for _ in range(TILE)]


def put(idx: Idx, x: int, y: int, v: int) -> None:
    idx[y % TILE][x % TILE] = v


def jitter(rng: random.Random, pts: list[tuple[float, float]], amt: float) -> list[tuple[float, float]]:
    return [(x + rng.uniform(-amt, amt), y + rng.uniform(-amt, amt)) for x, y in pts]


def nearest(sites: list[tuple[float, float]], x: int, y: int) -> list[tuple[float, int, float, float]]:
    """Sorted (distance, site, signed dx, signed dy) from pixel (x, y) to each site, wrapping at 16 px."""
    res: list[tuple[float, int, float, float]] = []
    for i, (sx, sy) in enumerate(sites):
        dx = (x - sx + TILE / 2) % TILE - TILE / 2
        dy = (y - sy + TILE / 2) % TILE - TILE / 2
        res.append((math.hypot(dx, dy), i, dx, dy))
    res.sort()
    return res


# ---------------------------------------------------------------- rendering

def blank() -> Grid:
    return [[(0, 0, 0, 0)] * TILE for _ in range(TILE)]


def paint(idx: Idx, palette: list[RGB], strength: float = 1.0, alpha: int = 255) -> Grid:
    """Map palette indices to graded RGBA. A negative index is transparent."""
    g = blank()
    for y in range(TILE):
        for x in range(TILE):
            i = idx[y][x]
            if i < 0:
                continue
            r, gg, b = grade(palette[clampi(i, 0, len(palette) - 1)], strength)
            g[y][x] = (r, gg, b, alpha)
    return g


def sprite(spec: list[tuple[int, int, str]], colours: dict[str, RGB]) -> Grid:
    """Draw (row, col, text) runs; each character names a colour. Other characters are skipped."""
    g = blank()
    for y, x, text in spec:
        for k, ch in enumerate(text):
            if ch in colours:
                r, gg, b = colours[ch]
                g[y % TILE][(x + k) % TILE] = (r, gg, b, 255)
    return g


def merge_sprite(base: Grid, over: Grid) -> Grid:
    return [[over[y][x] if over[y][x][3] else base[y][x] for x in range(TILE)] for y in range(TILE)]


# ---------------------------------------------------------------- stone family

STONE = ramp("#55555c", "#66666e", "#77777e", "#8a8a8f", "#9b9a9e", "#b0afb3")
ORE_EXT = ramp("#2a2a31", "#4d4d56", "#d3a27d", "#a8744f", "#efc9a0")  # 6 coal, 7 coal hi, 8 iron, 9 iron shade, 10 iron hi


def stone_idx(rng: random.Random) -> Idx:
    """Soft irregular slabs: Voronoi cells with a tone each, 1 px darker cracks at the seams."""
    pts = jitter(rng, [(2.5, 3.0), (9.0, 1.5), (13.5, 6.5), (5.5, 8.5), (11.0, 11.5), (2.0, 13.0)], 1.0)
    tone = [rng.choice((2, 3, 3, 4)) for _ in pts]
    grain = vnoise(rng, 8, 8)
    out = blank_idx()
    for y in range(TILE):
        for x in range(TILE):
            near = nearest(pts, x, y)
            d1, i, dx, dy = near[0]
            gap = near[1][0] - d1
            if gap < 0.9 and rng.random() < 0.8:
                out[y][x] = 0
                continue
            base = tone[i]
            g = grain[y][x]
            if g > 0.72:
                base += 1
            elif g < 0.28:
                base -= 1
            s = -(dx + dy) * light_weight(dx, dy)
            if s > 2.5:
                base += 1
            elif s < -2.5:
                base -= 1
            if rng.random() < 0.03:
                base = 5
            out[y][x] = clampi(base, 1, 5)
    return out


def _cobble_base(rng: random.Random) -> Idx:
    """Rounded cobbles: dark mortar on the cell seams, a rim shade and a top-left highlight."""
    pts = jitter(rng, [(3.5, 3.5), (10.5, 2.5), (14.0, 8.0), (7.0, 8.5), (2.5, 13.0), (11.0, 12.5)], 0.6)
    tone = [rng.choice((1, 2, 2, 3)) for _ in pts]
    grain = vnoise(rng, 8, 8)
    out = blank_idx()
    for y in range(TILE):
        for x in range(TILE):
            near = nearest(pts, x, y)
            d1, i, dx, dy = near[0]
            gap = near[1][0] - d1
            if gap < 1.1:
                out[y][x] = 0
                continue
            base = tone[i]
            if gap < 1.9:
                base -= 1
            s = -(dx + dy) / 1.4 * light_weight(dx, dy)
            if s > 1.6:
                base += 1
            elif s < -1.6:
                base -= 1
            g = grain[y][x]
            if g > 0.8:
                base += 1
            elif g < 0.2:
                base -= 1
            out[y][x] = clampi(base, 1, 4)
    return out


COBBLE = ramp("#4b4852", "#6c6a73", "#7d7b84", "#8f8d96", "#a6a4ad")
MOSS = ramp("#4b6236", "#58703d", "#667f48", "#748f55")  # used at 5..8 in the mossy palette


def cobble_idx(rng: random.Random) -> Idx:
    return _cobble_base(rng)


def mossy_idx(rng: random.Random) -> Idx:
    base = _cobble_base(rng)
    field = fbm(rng, [(4, 4, 1.0), (8, 8, 0.5)])
    biased = [[field[y][x] + (1.0 - y / (TILE - 1)) * 0.35 for x in range(TILE)] for y in range(TILE)]
    cover = top_mask(normalize(biased), 0.3)
    out = [row[:] for row in base]
    for y in range(TILE):
        for x in range(TILE):
            if cover[y][x]:
                out[y][x] = 5 + bucket(biased[y][x], 4)
    return out


def ore_cluster(rng: random.Random, base: Idx, body: int, hi: int, shade: int, n: int) -> None:
    """Small mineral clusters: body colour, a top-left highlight and a bottom-right shade."""
    for _ in range(n):
        cx, cy = rng.randrange(TILE), rng.randrange(TILE)
        cells = {(cx, cy), (cx + 1, cy), (cx, cy + 1)}
        if rng.random() < 0.7:
            cells.add((cx + 1, cy + 1))
        for x, y in cells:
            base[y % TILE][x % TILE] = body
        for x, y in cells:
            if (x - 1, y) not in cells or (x, y - 1) not in cells:
                base[y % TILE][x % TILE] = hi
            elif (x + 1, y) not in cells or (x, y + 1) not in cells:
                base[y % TILE][x % TILE] = shade


def coal_idx(rng: random.Random) -> Idx:
    base = stone_idx(rng_for("stone"))
    ore_cluster(rng, base, 6, 7, 6, rng.randint(4, 6))
    return base


def iron_idx(rng: random.Random) -> Idx:
    base = stone_idx(rng_for("stone"))
    ore_cluster(rng, base, 8, 10, 9, rng.randint(3, 5))
    return base


# ---------------------------------------------------------------- dirt and grass

DIRT = ramp("#4f3320", "#5e3f26", "#74502f", "#8a5f3c", "#9c6e46", "#6e6964", "#8a857f", "#a8a29b")


def dirt_idx(rng: random.Random) -> Idx:
    """Clumped dirt in four tones, grain, a few dark specks and two small pebbles."""
    f = fbm(rng, [(4, 4, 1.0), (8, 8, 0.5), (2, 2, 0.5)])
    out = [[1 + bucket(f[y][x], 4) for x in range(TILE)] for y in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            if rng.random() < 0.18:
                out[y][x] = clampi(out[y][x] + rng.choice((-1, 1)), 1, 4)
            if rng.random() < 0.02:
                out[y][x] = 0
    for _ in range(1):
        px, py = rng.randrange(TILE), rng.randrange(TILE)
        put(out, px, py, 7)
        put(out, px + 1, py, 6)
        put(out, px, py + 1, 6)
        put(out, px + 1, py + 1, 5)
    return out


GRASS_T = ramp("#7f8a76", "#8f9a84", "#a2ad94", "#b5bfa6", "#c6cdb8")


def grass_top_idx(rng: random.Random) -> Idx:
    f = fbm(rng, [(4, 4, 0.5), (16, 4, 1.0), (8, 8, 0.4)])
    out = [[1 + bucket(f[y][x], 3) for x in range(TILE)] for y in range(TILE)]
    for _ in range(34):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        put(out, x, y, 4)
        put(out, x, y + 1, 1)
    return out


GRASS_SIDE = ramp("#3f6027", "#4f7430", "#5f8a3a", "#72a046", "#84b256")  # 0..4, then DIRT at 5..12
SNOW_FRINGE = ramp("#b6c6da", "#c9d6e6", "#dbe5ef", "#eef3f8")  # 0..3, then DIRT at 4..11
SNOW = ramp("#c9d6e6", "#dbe5ef", "#e6edf5", "#f1f5f9")


def _fringe_lengths(rng: random.Random) -> list[int]:
    """Fringe length 3 or 4 per column, from a periodic wobble so column 15 meets column 0."""
    w = vnoise(rng, 4, 1)
    return [3 + (1 if w[0][x] > 0.5 else 0) for x in range(TILE)]


def grass_side_idx(rng: random.Random) -> Idx:
    d = dirt_idx(rng)
    out = [[v + 5 for v in row] for row in d]
    for x, length in enumerate(_fringe_lengths(rng)):
        drip = rng.random() < 0.12
        for y in range(length):
            if y == 0:
                v = 4 if rng.random() < 0.6 else 3
            elif y == length - 1:
                v = 1 if rng.random() < 0.7 else 0
            else:
                v = 2 if rng.random() < 0.6 else 3
            out[y][x] = v
        out[length][x] = 1 if drip else 5
    return out


def grass_side_snowed_idx(rng: random.Random) -> Idx:
    d = dirt_idx(rng)
    out = [[v + 4 for v in row] for row in d]
    for x, length in enumerate(_fringe_lengths(rng)):
        drip = rng.random() < 0.12
        for y in range(length):
            if y == 0:
                v = 3
            elif y == length - 1:
                v = 0
            else:
                v = 2 if rng.random() < 0.7 else 1
            out[y][x] = v
        out[length][x] = 0 if drip else 4
    return out


def snow_idx(rng: random.Random) -> Idx:
    f = fbm(rng, [(4, 4, 1.0), (8, 8, 0.4)])
    out = [[bucket(f[y][x], 4) for x in range(TILE)] for y in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            if rng.random() < 0.025:
                out[y][x] = 3
    return out


# ---------------------------------------------------------------- sand, sandstone, clay, gravel

SAND = ramp("#b9a86f", "#c9bb84", "#d8cb98", "#e4d8a9")


def sand_idx(rng: random.Random) -> Idx:
    """Fine two-tone grain with sparse darker specks."""
    f = fbm(rng, [(8, 8, 1.0), (2, 2, 0.5)])
    out = [[0] * TILE for _ in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            v = 0.4 * f[y][x] + 0.6 * rng.random()
            out[y][x] = 1 + (1 if v > 0.55 else 0) + (1 if v > 0.85 else 0) - (1 if v < 0.15 else 0)
            out[y][x] = clampi(out[y][x], 0, 3)
            if rng.random() < 0.03:
                out[y][x] = 0
    return out


SANDSTONE_TOP = ramp("#c8b884", "#d3c28b", "#dccf9a", "#e6d9a9")


def sandstone_top_idx(rng: random.Random) -> Idx:
    f = fbm(rng, [(4, 4, 1.0), (8, 8, 0.3)])
    out = [[1 + bucket(f[y][x], 3) for x in range(TILE)] for y in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            if rng.random() < 0.02:
                out[y][x] = 0
    return out


SANDSTONE_SIDE = ramp("#bfae78", "#cbbd86", "#d8cb98", "#e4d8a9")


def sandstone_side_idx(rng: random.Random) -> Idx:
    """Horizontal strata: bands of 3 to 4 rows, each with a darker line on its top row."""
    out = blank_idx()
    row = 0
    for height in (4, 3, 3, 3, 3):
        tone = rng.choice((1, 2, 2, 3))
        for k in range(height):
            for x in range(TILE):
                v = 0 if k == 0 else tone
                if v != 0 and rng.random() < 0.25:
                    v = clampi(v + rng.choice((-1, 1)), 1, 3)
                out[row][x] = v
            row += 1
    return out


CLAY = ramp("#737d8a", "#7f8a97", "#8b96a3", "#98a2ae", "#a5afba")


def clay_idx(rng: random.Random) -> Idx:
    f = fbm(rng, [(4, 4, 1.0), (8, 8, 0.3)])
    return [[bucket(f[y][x], 5) for x in range(TILE)] for y in range(TILE)]


GRAVEL = ramp("#4f4a45", "#5f5a54", "#716b64", "#837d75", "#958f87", "#a8a298")


def gravel_idx(rng: random.Random) -> Idx:
    pts = jitter(rng, [(2.0 + 4 * i, 2.0 + 4 * j) for i in range(4) for j in range(4)], 1.3)
    tone = [rng.choice((1, 2, 3, 4)) for _ in pts]
    out = blank_idx()
    for y in range(TILE):
        for x in range(TILE):
            near = nearest(pts, x, y)
            d1, i, dx, dy = near[0]
            if near[1][0] - d1 < 0.7:
                out[y][x] = 0
                continue
            base = tone[i]
            s = -(dx + dy) / 1.2 * light_weight(dx, dy)
            if s > 1.6:
                base += 1
            elif s < -1.6:
                base -= 1
            out[y][x] = clampi(base, 1, 5)
    return out


# ---------------------------------------------------------------- wood

BARK_OAK = ramp("#4a3521", "#5e4229", "#745233", "#8a6442", "#a07a4d")


def _wave_y(rng: random.Random) -> list[float]:
    """A periodic wobble along y, used to bend bark ridges and fissures."""
    w = vnoise(rng, 1, 4)
    return [w[y][0] - 0.5 for y in range(TILE)]


def log_oak_side_idx(rng: random.Random) -> Idx:
    wave = _wave_y(rng)
    out = blank_idx()
    for y in range(TILE):
        for x in range(TILE):
            r = math.cos(2 * math.pi * (x + 2.2 * wave[y]) / 4.0)
            out[y][x] = clampi(int((r + 1.0) * 2.5), 0, 4)
            if rng.random() < 0.15:
                out[y][x] = clampi(out[y][x] + rng.choice((-1, 1)), 0, 4)
    for _ in range(4):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        put(out, x, y, 0)
        put(out, x + 1, y, 0)
    return out


OAK_TOP = ramp("#4a3521", "#65482d", "#8a6442", "#a27a4b", "#b58d5c", "#c39f6c")


def _rings(rng: random.Random, spacing: float, pith_r: float, a: int, b: int, rim: list[int]) -> Idx:
    wob = vnoise(rng, 4, 4)
    out = blank_idx()
    for y in range(TILE):
        for x in range(TILE):
            r = math.hypot(x - 7.5, y - 7.5) + (wob[y][x] - 0.5) * 1.4
            if r > 6.6:
                out[y][x] = rim[0] if x + y < 14 else rim[1]
            elif r < pith_r:
                out[y][x] = a - 1
            else:
                k = int(r / spacing)
                v = a if k % 2 == 0 else b
                if rng.random() < 0.1:
                    v -= 1
                out[y][x] = v
    return out


def log_oak_top_idx(rng: random.Random) -> Idx:
    return _rings(rng, 1.2, 1.2, 3, 4, [1, 0])


def planks_oak_idx(rng: random.Random) -> Idx:
    """Four boards of three rows and a seam row. Seams sit on rows 2, 6, 10, 14 so the wrap is inside a board."""
    out = blank_idx()
    for b in range(4):
        top = (4 * b + 3) % TILE
        rows = [(top + k) % TILE for k in range(3)]
        tone = rng.choice((1, 2, 2, 3))
        for x in range(TILE):
            out[rows[0]][x] = clampi(tone + 1, 1, 4)
            out[rows[1]][x] = tone
            out[rows[2]][x] = clampi(tone - 1, 1, 4)
        for _ in range(2):
            gx = rng.randrange(TILE)
            for k in range(rng.randint(3, 6)):
                put(out, gx + k, rows[1], 0 if tone > 1 else 1)
        jx = rng.randrange(4, 13)
        for y in rows:
            put(out, jx, y, 5)
        put(out, 2, rows[1], 6)
        put(out, 13, rows[1], 6)
        put(out, 3, rows[2], 4)
        put(out, 12, rows[2], 4)
    for seam in (2, 6, 10, 14):
        for x in range(TILE):
            out[seam][x] = 0
    return out


PLANKS = ramp("#5a4226", "#8f6a3c", "#a07444", "#b08650", "#c09a62", "#6e5030", "#3f3024")


def _leaves(rng: random.Random, palette_len: int) -> Idx:
    f = fbm(rng, [(4, 4, 1.0), (8, 8, 0.5)])
    h = fbm(rng, [(8, 8, 1.0), (4, 4, 0.5)])
    holes = top_mask(h, 0.25)
    out = [[bucket(f[y][x], palette_len - 1) for x in range(TILE)] for y in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            if holes[y][x]:
                out[y][x] = -1
    for y in range(TILE):
        for x in range(TILE):
            if out[y][x] < 0:
                continue
            if holes[(y - 1) % TILE][x] or holes[y][(x - 1) % TILE]:
                out[y][x] = min(palette_len - 1, out[y][x] + 1)
            elif holes[(y + 1) % TILE][x] or holes[y][(x + 1) % TILE]:
                out[y][x] = max(0, out[y][x] - 1)
    return out


LEAVES_OAK = ramp("#7f8f70", "#8fa27c", "#a0b08a", "#b1bf99", "#c4d0aa")
LEAVES_BIRCH = ramp("#9aa67f", "#aab58c", "#bbc49b", "#ccd5ad", "#dbe2c0")
LEAVES_SPRUCE = ramp("#56675a", "#637567", "#71826f", "#7f8f7d", "#8e9e8b")


def leaves_oak_idx(rng: random.Random) -> Idx:
    return _leaves(rng, len(LEAVES_OAK))


def leaves_birch_idx(rng: random.Random) -> Idx:
    return _leaves(rng, len(LEAVES_BIRCH))


def leaves_spruce_idx(rng: random.Random) -> Idx:
    return _leaves(rng, len(LEAVES_SPRUCE))


BIRCH_BARK = ramp("#3f3a36", "#6a625a", "#b5ad9d", "#d4cdbd", "#e6e0d0", "#f1ece0")


def log_birch_side_idx(rng: random.Random) -> Idx:
    f = fbm(rng, [(2, 8, 1.0), (4, 16, 0.4)])
    out = [[3 + bucket(f[y][x], 3) for x in range(TILE)] for y in range(TILE)]
    for _ in range(16):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        v = 0 if rng.random() < 0.6 else 1
        for k in range(rng.choice((2, 3, 4))):
            put(out, x + k, y, v)
    for _ in range(3):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for k in range(3):
            put(out, x + k, y, 2)
    return out


BIRCH_TOP = ramp("#4b3b2b", "#b9a072", "#cdb983", "#dccb9a", "#e6e0d0", "#3f3a36")


def log_birch_top_idx(rng: random.Random) -> Idx:
    out = _rings(rng, 0.9, 1.0, 3, 2, [4, 4])
    for y in range(TILE):
        for x in range(TILE):
            if out[y][x] == 4 and rng.random() < 0.12:
                out[y][x] = 5
    return out


SPRUCE_BARK = ramp("#241a10", "#2c2018", "#3a2a1e", "#4a3626", "#5c4530", "#6b5440")


def log_spruce_side_idx(rng: random.Random) -> Idx:
    """Deep vertical fissures between irregular plates; plate edges catch light."""
    wave = _wave_y(rng)
    fis = [[False] * TILE for _ in range(TILE)]
    for x0 in (rng.randrange(TILE) for _ in range(3)):
        for y in range(TILE):
            x = int(round(x0 + wave[y] * 2.5)) % TILE
            fis[y][x] = True
            if rng.random() < 0.45:
                fis[y][(x + 1) % TILE] = True
    f = fbm(rng, [(2, 8, 1.0), (8, 2, 0.5)])
    out = [[2 + bucket(f[y][x], 3) for x in range(TILE)] for y in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            if fis[y][x]:
                out[y][x] = 0 if not fis[y][(x - 1) % TILE] else 1
            elif fis[y][(x - 1) % TILE]:
                out[y][x] += 1
            elif fis[y][(x + 1) % TILE]:
                out[y][x] -= 1
            if rng.random() < 0.04 and not fis[y][x]:
                out[y][x] = 5
            out[y][x] = clampi(out[y][x], 0, 5)
    return out


SPRUCE_TOP = ramp("#3a2a1e", "#2c2018", "#5c4530", "#7a5c3c", "#8f6d48", "#a58156")


def log_spruce_top_idx(rng: random.Random) -> Idx:
    return _rings(rng, 0.75, 1.0, 3, 4, [1, 0])


WATER = ramp("#3d6fb0", "#4a7ebb", "#5a8fd0", "#6b9fde", "#9cc4ec")


def water_idx(rng: random.Random) -> Idx:
    """Horizontal ripple streaks with sparse crest highlights."""
    f = fbm(rng, [(3, 8, 1.0), (2, 4, 0.6)])
    out = [[bucket(f[y][x], 4) for x in range(TILE)] for y in range(TILE)]
    for y in range(TILE):
        for x in range(TILE):
            if out[y][x] == 3 and rng.random() < 0.3:
                out[y][x] = 4
    return out


# ---------------------------------------------------------------- plants

GRASS_PLANT = GRASS_T


def tall_grass_idx(rng: random.Random) -> Idx:
    out = blank_idx(-1)
    for _ in range(10):
        bx = rng.randrange(1, 15)
        h = rng.randint(5, 11)
        lean = rng.choice((-1, 0, 0, 1))
        for t in range(h + 1):
            x = bx + int(round(lean * (t / h) * 2))
            y = TILE - 1 - t
            put(out, x, y, 4 if t == h else (2 if rng.random() < 0.6 else 1))
            if t < h - 1 and rng.random() < 0.3:
                put(out, x + 1, y, 0)
    return out


FERN = ramp("#6f7d66", "#829276", "#95a587", "#a8b898", "#bccab0")


def fern_idx(rng: random.Random) -> Idx:
    """A clump of arching fronds: a curved stem with short leaflets on both sides, longest at the base."""
    out = blank_idx(-1)
    fronds = [
        ((8.0, 15.0), (9.0, 7.0), (13.0, 4.0)),
        ((8.0, 15.0), (6.0, 8.0), (2.0, 5.0)),
        ((8.0, 15.0), (4.0, 13.0), (0.0, 10.0)),
        ((8.0, 15.0), (12.0, 13.0), (15.0, 11.0)),
    ]
    steps = 12
    for p0, p1, p2 in fronds:
        prev = None
        for i in range(steps + 1):
            t = i / steps
            bx = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            by = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
            put(out, int(round(bx)), int(round(by)), 1)
            if prev is not None:
                dx, dy = bx - prev[0], by - prev[1]
                norm = math.hypot(dx, dy) or 1.0
                nx, ny = -dy / norm, dx / norm
                if i >= 2 and i % 2 == 0 and i < steps:
                    ln = max(1, round(3.0 * (1.0 - t)))
                    for k in range(1, ln + 1):
                        for sign, tone in ((1, 3), (-1, 2)):
                            lx = bx + sign * nx * k
                            ly = by + sign * ny * k
                            v = tone if k < ln else 2
                            if int(round(ly)) >= 2:
                                put(out, int(round(lx)), int(round(ly)), v)
            prev = (bx, by)
        put(out, int(round(p2[0])), int(round(p2[1])), 4)
    return out


FLOWER_STEM = {"G": hx("#4f7a33"), "g": hx("#6f9a45"), "d": hx("#3f6428")}


def _stem_spec() -> list[tuple[int, int, str]]:
    return [(11, 7, "G"), (12, 7, "G"), (13, 7, "G"), (14, 7, "G"), (15, 7, "G"),
            (12, 5, "dg"), (14, 8, "gd")]


def flower_red(rng: random.Random) -> Grid:
    colours = {"R": hx("#d1483a"), "r": hx("#a83428"), "C": hx("#3a2a22"), **FLOWER_STEM}
    spec = [(8, 6, "r" + "R" + "R" + "r"), (9, 5, "RR" + "CC" + "RR"), (10, 6, "rRRr")] + _stem_spec()
    return sprite(spec, colours)


def flower_yellow(rng: random.Random) -> Grid:
    colours = {"Y": hx("#f0cf4a"), "y": hx("#d9a92f"), "C": hx("#b9841f"), **FLOWER_STEM}
    spec = [(8, 6, "yYYy"), (9, 5, "YYCCYY"), (10, 6, "yYYy")] + _stem_spec()
    return sprite(spec, colours)


def flower_blue(rng: random.Random) -> Grid:
    colours = {"B": hx("#4f8fe0"), "b": hx("#2e5fa8"), **FLOWER_STEM}
    spec = [(8, 6, "B.B"), (9, 7, "b"), (10, 6, "B.B")] + _stem_spec()
    return sprite(spec, colours)


def flower_white(rng: random.Random) -> Grid:
    colours = {"w": hx("#f2f4f6"), "Y": hx("#e6c04a"), **FLOWER_STEM}
    spec = [(8, 7, "w"), (9, 6, "wYw"), (10, 7, "w")] + _stem_spec()
    return sprite(spec, colours)


def dead_bush(rng: random.Random) -> Grid:
    colours = {"d": hx("#5c4226"), "l": hx("#8a6a44")}
    paths = [
        [(15, 8), (14, 8), (13, 7), (12, 7), (11, 6), (10, 5), (9, 4)],
        [(12, 7), (11, 8), (10, 9), (9, 10)],
        [(14, 8), (13, 9), (12, 10), (11, 11), (10, 12)],
        [(11, 6), (10, 6), (9, 6)],
        [(13, 7), (13, 6)],
    ]
    spec: list[tuple[int, int, str]] = []
    for pi, path in enumerate(paths):
        for k, (y, x) in enumerate(path):
            spec.append((y, x, "l" if (pi + k) % 3 == 0 else "d"))
    return sprite(spec, colours)


def mushroom_brown(rng: random.Random) -> Grid:
    colours = {"c": hx("#8a6446"), "H": hx("#a57c58"), "k": hx("#5e4030"),
               "u": hx("#6e4c36"), "s": hx("#e8dcc4"), "S": hx("#c9b899")}
    spec = [(8, 5, "k" + "H" * 4 + "k"), (9, 4, "k" + "c" * 6 + "k"), (10, 4, "k" + "u" * 6 + "k")]
    spec += [(y, 7, "sS") for y in range(11, 16)]
    return sprite(spec, colours)


def mushroom_red(rng: random.Random) -> Grid:
    colours = {"R": hx("#c23f2e"), "r": hx("#8f2a20"), "W": hx("#f2ece0"),
               "s": hx("#e8dcc4"), "S": hx("#c9b899")}
    spec = [(7, 5, "r" + "R" * 4 + "r"), (8, 4, "rRWRRWRr"), (9, 4, "r" * 8)]
    spec += [(y, 7, "sS") for y in range(10, 16)]
    return sprite(spec, colours)


# ---------------------------------------------------------------- generator table

def _flat(fn: Callable[[random.Random], Idx], pal: list[RGB], strength: float = 1.0) -> Callable[[random.Random], Grid]:
    def run(rng: random.Random) -> Grid:
        return paint(fn(rng), pal, strength)
    return run


def _grass_side(rng: random.Random) -> Grid:
    return paint(grass_side_idx(rng), GRASS_SIDE + DIRT)


def _grass_side_snowed(rng: random.Random) -> Grid:
    return paint(grass_side_snowed_idx(rng), SNOW_FRINGE + DIRT)


def _mossy(rng: random.Random) -> Grid:
    return paint(mossy_idx(rng), COBBLE + MOSS)


def _ore(fn: Callable[[random.Random], Idx]) -> Callable[[random.Random], Grid]:
    def run(rng: random.Random) -> Grid:
        return paint(fn(rng), STONE + ORE_EXT)
    return run


def _leaves_grid(fn: Callable[[random.Random], Idx], pal: list[RGB]) -> Callable[[random.Random], Grid]:
    def run(rng: random.Random) -> Grid:
        return paint(fn(rng), pal)
    return run


GENERATORS: dict[str, Callable[[random.Random], Grid]] = {
    "grass_top": _flat(grass_top_idx, GRASS_T),
    "grass_side": _grass_side,
    "dirt": _flat(dirt_idx, DIRT),
    "stone": _flat(stone_idx, STONE),
    "cobblestone": _flat(cobble_idx, COBBLE),
    "gravel": _flat(gravel_idx, GRAVEL),
    "sand": _flat(sand_idx, SAND),
    "sandstone_top": _flat(sandstone_top_idx, SANDSTONE_TOP),
    "sandstone_side": _flat(sandstone_side_idx, SANDSTONE_SIDE),
    "clay": _flat(clay_idx, CLAY),
    "snow": _flat(snow_idx, SNOW, 0.35),
    "grass_side_snowed": _grass_side_snowed,
    "log_oak_side": _flat(log_oak_side_idx, BARK_OAK),
    "log_oak_top": _flat(log_oak_top_idx, OAK_TOP),
    "planks_oak": _flat(planks_oak_idx, PLANKS),
    "leaves_oak": _leaves_grid(leaves_oak_idx, LEAVES_OAK),
    "log_birch_side": _flat(log_birch_side_idx, BIRCH_BARK),
    "log_birch_top": _flat(log_birch_top_idx, BIRCH_TOP),
    "leaves_birch": _leaves_grid(leaves_birch_idx, LEAVES_BIRCH),
    "log_spruce_side": _flat(log_spruce_side_idx, SPRUCE_BARK),
    "log_spruce_top": _flat(log_spruce_top_idx, SPRUCE_TOP),
    "leaves_spruce": _leaves_grid(leaves_spruce_idx, LEAVES_SPRUCE),
    "water": lambda rng: paint(water_idx(rng), WATER, 0.5, alpha=200),
    "tall_grass": _flat(tall_grass_idx, GRASS_PLANT),
    "fern": _flat(fern_idx, FERN),
    "flower_red": flower_red,
    "flower_yellow": flower_yellow,
    "flower_blue": flower_blue,
    "flower_white": flower_white,
    "dead_bush": dead_bush,
    "mushroom_brown": mushroom_brown,
    "mushroom_red": mushroom_red,
    "coal_ore": _ore(coal_idx),
    "iron_ore": _ore(iron_idx),
    "mossy_cobblestone": _mossy,
}

assert set(GENERATORS) == set(NAMES), "generator table and NAMES disagree"
assert len(NAMES) <= COLS * COLS


def build_tiles() -> dict[str, Grid]:
    tiles: dict[str, Grid] = {}
    for name in NAMES:
        tiles[name] = GENERATORS[name](rng_for(name))
    return tiles


def fill_transparent_rgb(g: Grid) -> Grid:
    """Give see-through pixels the average opaque colour so mipmaps do not pick up dark fringes."""
    opaque = [p for row in g for p in row if p[3] > 0]
    if not opaque:
        return g
    avg = tuple(int(round(sum(p[c] for p in opaque) / len(opaque))) for c in range(3))
    return [[p if p[3] > 0 else (avg[0], avg[1], avg[2], 0) for p in row] for row in g]


def grid_to_image(g: Grid) -> Image.Image:
    img = Image.new("RGBA", (TILE, TILE))
    img.putdata([p for row in g for p in row])
    return img


def build_atlas(tiles: dict[str, Grid]) -> Image.Image:
    atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (0, 0, 0, 0))
    for i, name in enumerate(NAMES):
        atlas.paste(grid_to_image(fill_transparent_rgb(tiles[name])), ((i % COLS) * TILE, (i // COLS) * TILE))
    return atlas


def _font(size: int) -> ImageFont.ImageFont | ImageFont.FreeTypeFont:
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def build_preview(tiles: dict[str, Grid]) -> Image.Image:
    font = _font(11)
    cell_w = TILE * PREVIEW_SCALE + 14
    cell_h = TILE * PREVIEW_SCALE + 18
    per_row = 7
    rows = math.ceil(len(NAMES) / per_row)
    grid_w = per_row * cell_w + 14
    grid_h = rows * cell_h + 14
    tiling_h = 26 + 4 * TILE * TILING_SCALE + 24
    tiling_w = 5 * (4 * TILE * TILING_SCALE + 18) + 14
    sheet = Image.new("RGBA", (max(grid_w, tiling_w), grid_h + tiling_h), BG + (255,))
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(NAMES):
        cx = 14 + (i % per_row) * cell_w
        cy = 14 + (i // per_row) * cell_h
        tile = grid_to_image(fill_transparent_rgb(tiles[name])).resize(
            (TILE * PREVIEW_SCALE, TILE * PREVIEW_SCALE), Image.Resampling.NEAREST)
        sheet.alpha_composite(tile, (cx, cy + 16))
        draw.text((cx, cy), name, fill=(220, 220, 220, 255), font=font)
    tint = hx(TINTS["grass"]["plains"])
    tiling_names = ["grass_top", "stone", "sand", "dirt", "water"]
    ty0 = grid_h + 12
    draw.text((14, ty0), "4x4 tiling check (grass_top shown tinted plains)", fill=(220, 220, 220, 255), font=font)
    for k, name in enumerate(tiling_names):
        base = grid_to_image(fill_transparent_rgb(tiles[name]))
        if name == "grass_top":
            pix = base.load()
            for y in range(TILE):
                for x in range(TILE):
                    r, g, b, a = pix[x, y]
                    pix[x, y] = (r * tint[0] // 255, g * tint[1] // 255, b * tint[2] // 255, a)
        big = Image.new("RGBA", (4 * TILE, 4 * TILE))
        for ty in range(4):
            for tx in range(4):
                big.paste(base, (tx * TILE, ty * TILE))
        big = big.resize((4 * TILE * TILING_SCALE, 4 * TILE * TILING_SCALE), Image.Resampling.NEAREST)
        ox = 14 + k * (4 * TILE * TILING_SCALE + 18)
        oy = ty0 + 26
        draw.text((ox, oy - 14), name, fill=(220, 220, 220, 255), font=font)
        sheet.alpha_composite(big, (ox, oy))
    return sheet


def write_outputs() -> None:
    tiles = build_tiles()
    os.makedirs(os.path.dirname(ATLAS_PNG), exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW_PNG), exist_ok=True)
    build_atlas(tiles).save(ATLAS_PNG, format="PNG", optimize=False)
    data = {
        "tile_size": TILE,
        "tiles": {name: i for i, name in enumerate(NAMES)},
        "tints": TINTS,
    }
    with open(ATLAS_JSON, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(data, indent=2) + "\n")
    build_preview(tiles).convert("RGB").save(PREVIEW_PNG, format="PNG", optimize=False)
    print(f"wrote {ATLAS_PNG}")
    print(f"wrote {ATLAS_JSON}")
    print(f"wrote {PREVIEW_PNG}")


if __name__ == "__main__":
    write_outputs()
