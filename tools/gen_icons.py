#!/usr/bin/env python3
"""Generates our own inventory icons: the Party Ball (T-22) and the four capture balls (T-26).

Pure stdlib (zlib, struct), so it runs anywhere Python 3 does. The art is drawn here, pixel by pixel; it is not
copied from any game. Outputs (relative to the repo root, unless paths are given):
  mods/minemon/minemon_party/textures/minemon_party_ball.png        the Party Ball, a red and white sphere
  mods/minemon/minemon_capture/textures/minemon_capture_<id>.png    poke_ball, great_ball, ultra_ball, master_ball
  mods/minemon/minemon_dread/textures/minemon_dread_shard.png       the Dread Shard (T-30)
  mods/minemon/minemon_dread/textures/minemon_capture_umbral_ball.png  the Umbral Ball (T-30)

Usage: python3 tools/gen_icons.py [party_output_dir] [capture_output_dir]
"""

import math
import os
import struct
import sys
import zlib

SIZE = 16
RADIUS = 7.0
CENTRE = (SIZE - 1) / 2.0
RED = (212, 42, 42)
WHITE = (242, 242, 242)
BLACK = (24, 24, 24)
BLUE = (48, 96, 210)
YELLOW = (250, 206, 40)
PURPLE = (120, 56, 168)
MARK_RED = (220, 40, 40)
SHADE = 0.82  # the lower red half is a little darker, so the sphere reads as round
TRANSPARENT = (0, 0, 0, 0)

# The M of the Master Ball, 5 pixels wide and 4 tall, drawn in the top half of the sphere.
M_GLYPH = [
    "1...1",
    "11.11",
    "1.1.1",
    "1...1",
]
M_ORIGIN = (5, 3)  # x, y of the glyph's top left pixel


def _shaded(colour, dark):
    """The colour, darkened by SHADE for the lower half when dark is true."""
    if not dark:
        return colour
    r, g, b = colour
    return (int(r * SHADE), int(g * SHADE), int(b * SHADE))


def ball_pixel(x, y):
    """RGBA for pixel (x, y) of the Party Ball."""
    dx = x - CENTRE
    dy = y - CENTRE
    dist = (dx * dx + dy * dy) ** 0.5
    if dist > RADIUS:
        return TRANSPARENT
    if dist > RADIUS - 1.0:
        return BLACK + (255,)
    # The belt across the middle: a black band, two pixels tall.
    if abs(dy) < 1.0:
        return BLACK + (255,)
    # The centre button: white with a black ring.
    if dist < 2.3:
        if dist > 1.3:
            return BLACK + (255,)
        return WHITE + (255,)
    if dy < 0:
        r, g, b = RED
    else:
        r, g, b = _shaded(WHITE, True)
    return (r, g, b, 255)


def sphere_pixel(x, y, top, bottom, button_ring=BLACK, marks=None, glyph=None):
    """RGBA for pixel (x, y) of a capture ball: a top colour, a bottom colour, a black belt and a centre button.

    marks: set of (x, y) pixels of the bottom half drawn in MARK_RED. glyph: set of (x, y) pixels drawn in WHITE.
    """
    dx = x - CENTRE
    dy = y - CENTRE
    dist = (dx * dx + dy * dy) ** 0.5
    if dist > RADIUS:
        return TRANSPARENT
    if dist > RADIUS - 1.0:
        return BLACK + (255,)
    if abs(dy) < 1.0:
        return BLACK + (255,)
    if dist < 2.3:
        if dist > 1.3:
            return button_ring + (255,)
        return WHITE + (255,)
    if glyph and (x, y) in glyph:
        return WHITE + (255,)
    if dy < 0:
        r, g, b = top
    else:
        if marks and (x, y) in marks:
            return MARK_RED + (255,)
        r, g, b = bottom
    return (r, g, b, 255)


def _glyph_pixels():
    out = set()
    for row, line in enumerate(M_GLYPH):
        for col, ch in enumerate(line):
            if ch == "1":
                out.add((M_ORIGIN[0] + col, M_ORIGIN[1] + row))
    return out


def capture_rows(name):
    """The rows of one capture ball, by ball id."""
    if name == "poke_ball":
        # Red top, white bottom: the Poké Ball.
        def px(x, y):
            return sphere_pixel(x, y, RED, WHITE)
    elif name == "great_ball":
        # Blue top, white bottom, with red marks on the white half.
        marks = {(4, 10), (5, 11), (10, 10), (11, 11)}

        def px(x, y):
            return sphere_pixel(x, y, BLUE, WHITE, marks=marks)
    elif name == "ultra_ball":
        # Black top, yellow bottom.
        def px(x, y):
            return sphere_pixel(x, y, BLACK, YELLOW, button_ring=BLACK)
    elif name == "master_ball":
        # Purple top with a white M, white bottom.
        glyph = _glyph_pixels()

        def px(x, y):
            return sphere_pixel(x, y, PURPLE, WHITE, glyph=glyph)
    else:
        raise ValueError("unknown capture ball: " + name)
    return [[px(x, y) for x in range(SIZE)] for y in range(SIZE)]


CAPTURE_BALLS = ("poke_ball", "great_ball", "ultra_ball", "master_ball")


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


# Evolution items (T-27, D-030): our own 16x16 stones (gems), held items and the Link Cable (coins and a cable).
# Drawn here, pixel by pixel, from simple shapes; not copied from any game. Kept apart from the ball icon above.
EVO_OUTLINE = (24, 24, 24)
EVO_GEMS = {
    "fire_stone": (220, 60, 40),
    "water_stone": (60, 130, 235),
    "thunder_stone": (250, 215, 60),
    "leaf_stone": (80, 200, 90),
    "moon_stone": (190, 180, 235),
    "sun_stone": (255, 160, 40),
}
EVO_COINS = {
    "dragon_scale": (50, 160, 150),
    "king_s_rock": (214, 170, 60),
    "metal_coat": (176, 184, 196),
    "up_grade": (110, 130, 170),
}
CABLE_WIRE = (70, 70, 80)
CABLE_HIGHLIGHT = (125, 125, 136)
CABLE_PLUG = (200, 200, 210)


def _shade(base, factor):
    return tuple(int(c * factor) for c in base)


def gem_pixel(x, y, base):
    """A diamond with a lit top half and a darker bottom half."""
    dx = x - CENTRE
    dy = y - CENTRE
    d = abs(dx) + abs(dy)
    if d > 6.0:
        return TRANSPARENT
    if d >= 6.0:
        return EVO_OUTLINE + (255,)
    if dy < -2.5:
        r, g, b = tuple(min(255, c + 60) for c in base)
    elif dy > 2.5:
        r, g, b = _shade(base, 0.7)
    else:
        r, g, b = base
    return (r, g, b, 255)


def coin_pixel(x, y, base):
    """A round coin: a rim, a raised centre ring and a shaded lower-right side."""
    dx = x - CENTRE
    dy = y - CENTRE
    dist = (dx * dx + dy * dy) ** 0.5
    if dist > 6.5:
        return TRANSPARENT
    if dist > 5.8:
        return EVO_OUTLINE + (255,)
    if dist > 4.9:
        r, g, b = _shade(base, 0.7)
    elif 1.4 < dist < 2.6:
        r, g, b = tuple(min(255, c + 50) for c in base)
    elif dx + dy > 2.5:
        r, g, b = _shade(base, 0.85)
    else:
        r, g, b = base
    return (r, g, b, 255)


def cable_pixel(x, y, plug_top, plug_bottom):
    """A Link Cable: a wire curving from the top-left plug to the bottom-right plug."""
    if plug_top(x, y):
        return (CABLE_PLUG if not plug_top.edge(x, y) else EVO_OUTLINE) + (255,)
    if plug_bottom(x, y):
        return (CABLE_PLUG if not plug_bottom.edge(x, y) else EVO_OUTLINE) + (255,)
    # The wire: y follows x from (3, 3) to (12, 12), bowed by a sine so it reads as a cable, about 2 px thick.
    t = x - 3.0
    wire_y = 3.0 + t + 2.5 * math.sin(math.pi * t / 9.0) if 0.0 <= t <= 9.0 else None
    if wire_y is not None and abs(y - wire_y) <= 1.0:
        return CABLE_HIGHLIGHT + (255,) if y < wire_y else CABLE_WIRE + (255,)
    return TRANSPARENT


class _Rect:
    """A plug: a filled rectangle with a one-pixel outline, drawn over the wire."""

    def __init__(self, x0, y0, x1, y1):
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1

    def __call__(self, x, y):
        return self.x0 <= x <= self.x1 and self.y0 <= y <= self.y1

    def edge(self, x, y):
        return x in (self.x0, self.x1) or y in (self.y0, self.y1)


def write_evolution_icons(out_dir):
    """Writes minemon_evo_<item>.png for the six stones, four held items and the Link Cable. Returns the paths."""
    os.makedirs(out_dir, exist_ok=True)
    plug_top = _Rect(1, 1, 5, 4)
    plug_bottom = _Rect(10, 10, 14, 14)
    jobs = []
    for item, base in EVO_GEMS.items():
        jobs.append((item, [[gem_pixel(x, y, base) for x in range(SIZE)] for y in range(SIZE)]))
    for item, base in EVO_COINS.items():
        jobs.append((item, [[coin_pixel(x, y, base) for x in range(SIZE)] for y in range(SIZE)]))
    cable = [[cable_pixel(x, y, plug_top, plug_bottom) for x in range(SIZE)] for y in range(SIZE)]
    jobs.append(("link_cable", cable))
    paths = []
    for item, rows in jobs:
        path = os.path.join(out_dir, "minemon_evo_%s.png" % item)
        with open(path, "wb") as f:
            f.write(png_bytes(SIZE, SIZE, rows))
        paths.append(os.path.normpath(path))
    return paths


DREAD_BODY = (34, 14, 48)  # the shard: a black-violet crystal
DREAD_FACET = (112, 52, 164)  # the lit facet on the left
DREAD_HIGHLIGHT = (176, 124, 224)
DREAD_GLINT = (200, 22, 52)  # the deep red glints (T-30)
DREAD_EDGE = (10, 4, 16)
UMBRAL_TOP = (26, 18, 36)
UMBRAL_BOTTOM = (16, 12, 22)
UMBRAL_BAND = (130, 60, 190)  # the violet band of the Umbral Ball
UMBRAL_BUTTON = (150, 80, 210)


def dread_shard_pixel(x, y):
    """RGBA for pixel (x, y) of the Dread Shard (T-30): a tall jagged crystal, black-violet, with red glints."""
    t = (y - 1) / 13.0
    if t < 0.0 or t > 1.0:
        return TRANSPARENT
    # Jagged edges: the half width follows a sine profile, with a sawtooth of one pixel on the rows.
    jag = (0.0, 0.9, 0.2, -0.7, 0.5, -0.4, 0.8, -0.2, 0.3, -0.8, 0.1, 0.6, -0.5, 0.2)[y - 1]
    half = 4.6 * math.sin(math.pi * t) ** 0.8 + jag * 0.5
    dx = x - 7.5
    if abs(dx) > half:
        return TRANSPARENT
    if abs(dx) > half - 1.0:
        return DREAD_EDGE + (255,)
    if (x, y) in ((9, 6), (10, 8), (8, 11)):
        return DREAD_GLINT + (255,)
    if (x, y) in ((6, 3), (6, 4), (5, 5)):
        return DREAD_HIGHLIGHT + (255,)
    if dx < -half * 0.3:
        return DREAD_FACET + (255,)
    return DREAD_BODY + (255,)


def umbral_pixel(x, y):
    """RGBA for pixel (x, y) of the Umbral Ball (T-30): black, with a violet band across the middle."""
    dx = x - CENTRE
    dy = y - CENTRE
    dist = (dx * dx + dy * dy) ** 0.5
    if dist > RADIUS:
        return TRANSPARENT
    if dist > RADIUS - 1.0:
        return DREAD_EDGE + (255,)
    if abs(dy) < 1.0:
        return UMBRAL_BAND + (255,)
    if dist < 2.3:
        return (DREAD_EDGE if dist > 1.3 else UMBRAL_BUTTON) + (255,)
    if dy < 0:
        if dist > RADIUS - 2.2 and dx < 0:
            return (60, 30, 90, 255)  # a rim highlight on the upper left
        return UMBRAL_TOP + (255,)
    return UMBRAL_BOTTOM + (255,)


def write_dread_icons(out_dir):
    """Writes minemon_dread_shard.png and minemon_capture_umbral_ball.png (T-30). Returns the paths."""
    os.makedirs(out_dir, exist_ok=True)
    jobs = [
        ("minemon_dread_shard.png", [[dread_shard_pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]),
        ("minemon_capture_umbral_ball.png", [[umbral_pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]),
    ]
    paths = []
    for name, rows in jobs:
        path = os.path.join(out_dir, name)
        with open(path, "wb") as f:
            f.write(png_bytes(SIZE, SIZE, rows))
        paths.append(os.path.normpath(path))
    return paths


def _write(path, rows):
    with open(path, "wb") as f:
        f.write(png_bytes(SIZE, SIZE, rows))
    print("wrote " + os.path.normpath(path))


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    party_dir = argv[1] if len(argv) > 1 else os.path.join(here, "..", "mods", "minemon", "minemon_party", "textures")
    capture_dir = argv[2] if len(argv) > 2 else os.path.join(here, "..", "mods", "minemon", "minemon_capture",
                                                             "textures")
    os.makedirs(party_dir, exist_ok=True)
    os.makedirs(capture_dir, exist_ok=True)
    rows = [[ball_pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]
    _write(os.path.join(party_dir, "minemon_party_ball.png"), rows)
    for name in CAPTURE_BALLS:
        _write(os.path.join(capture_dir, "minemon_capture_" + name + ".png"), capture_rows(name))
    evo_dir = os.path.join(here, "..", "mods", "minemon", "minemon_growth", "textures")
    for evo_path in write_evolution_icons(evo_dir):
        print("wrote " + evo_path)
    dread_dir = os.path.join(here, "..", "mods", "minemon", "minemon_dread", "textures")
    for dread_path in write_dread_icons(dread_dir):
        print("wrote " + dread_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
