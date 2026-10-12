#!/usr/bin/env python3
"""VFX particle textures for minemon_combat (T-23): 8x8 white soft orb, spark and puff PNGs.

Writes, deterministically and with the Python standard library only (PNG writer from gen_standins.py):
  mods/minemon/minemon_combat/textures/minemon_combat_orb.png    soft round glow
  mods/minemon/minemon_combat/textures/minemon_combat_spark.png  four-point spark
  mods/minemon/minemon_combat/textures/minemon_combat_puff.png   mottled smoke puff

All three are white with an alpha channel. vfx.lua tints them per move type with the texture modifier
"^[multiply:#rrggbb", so one file serves all 17 types. Project-owned art (CC0, see ASSETS_LICENSES.md).
Usage: python3 tools/gen_vfx.py   (any working directory)
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEX_DIR = os.path.join(ROOT, "mods", "minemon", "minemon_combat", "textures")
sys.path.insert(0, HERE)

from gen_standins import write_png  # noqa: E402  (the shared PNG writer, stdlib only)

SIZE = 8
CENTRE = (SIZE - 1) / 2.0


def clamp01(v):
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def hash01(x, y):
    """Deterministic pseudo-random value in 0..1 for a pixel."""
    h = (x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995
    h = (h * 2654435761) & 0xFFFFFFFF
    return ((h >> 8) & 0xFFFF) / 65535.0


def orb_alpha(x, y):
    d = (((x - CENTRE) ** 2 + (y - CENTRE) ** 2) ** 0.5) / (SIZE / 2.0)
    return clamp01(1.0 - d) ** 1.6


def spark_alpha(x, y):
    dx, dy = abs(x - CENTRE), abs(y - CENTRE)
    arm = max(0.0, 1.0 - min(dx, dy) / 0.8) * max(0.0, 1.0 - max(dx, dy) / (SIZE / 2.0))
    core = clamp01(1.0 - (dx + dy) / 1.6)
    return clamp01(max(arm, core))


def puff_alpha(x, y):
    d = (((x - CENTRE) ** 2 + (y - CENTRE) ** 2) ** 0.5) / (SIZE / 2.0)
    falloff = clamp01(1.0 - d) ** 0.8
    return falloff * (0.55 + 0.45 * hash01(x, y))


def make(alpha_fn):
    img = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            a = int(round(255 * alpha_fn(x, y)))
            row.append((255, 255, 255, a))
        img.append(row)
    return img


def write_all(tex_dir=TEX_DIR):
    os.makedirs(tex_dir, exist_ok=True)
    outputs = {
        "minemon_combat_orb.png": orb_alpha,
        "minemon_combat_spark.png": spark_alpha,
        "minemon_combat_puff.png": puff_alpha,
    }
    for name, fn in outputs.items():
        write_png(os.path.join(tex_dir, name), make(fn))
    return sorted(outputs)


def main():
    names = write_all()
    print("wrote %d textures to %s: %s" % (len(names), TEX_DIR, ", ".join(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
