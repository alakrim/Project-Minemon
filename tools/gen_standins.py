#!/usr/bin/env python3
"""Procedural stand-in creatures (T-18): our own blocky models and 32x32 type textures.

Writes, deterministically and with the Python standard library only:
  mods/minemon/minemon_creatures/models/mm_<plan>.glb            8 body plans (glTF 2.0 binary)
  mods/minemon/minemon_creatures/textures/mm_type_<type>.png     17 types
  mods/minemon/minemon_creatures/textures/mm_type_<type>_shiny.png  hue-shifted variants

Every model is a skinned set of boxes: one joint per body part (rigid, weight 1.0), and ONE glTF
animation clip. Frame ranges (glTF times are seconds, see Luanti lua_api.md "glTF"):
  stand 0-20 (loop), walk 21-41 (loop), run 42-52 (loop), punch 53-63, die 64-74, sit 75-85 (both play once).
Play with set_animation(range, speed, blend, loop) where speed is in frames per second, i.e. the
clip time units. Recommended speeds are listed in docs in T-18's report.

Art is project-owned (CC0, see ASSETS_LICENSES.md). No Pokemon design is used or imitated; species
data is not read here. Usage: python3 tools/gen_standins.py   (any working directory)
"""

import colorsys
import hashlib
import json
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MEDIA_DIR = os.path.join(ROOT, "mods", "minemon", "minemon_creatures")
MODEL_DIR = os.path.join(MEDIA_DIR, "models")
TEX_DIR = os.path.join(MEDIA_DIR, "textures")

UNITS = 10.0  # glTF units per node (Luanti: 10 glTF units = 1 node)
TEX = 32
TAU = 2.0 * math.pi
SAMPLES = 8  # keyframe steps per frame range (periodic ranges reuse the first sample at the end)

PLANS = ["biped", "quadruped", "serpent", "avian", "blob", "insect", "fish", "other"]

# name -> (base colour, accent colour, glowing eye colour or None)
PALETTE = {
    "normal": ((178, 164, 136), (236, 224, 196), None),
    "fire": ((214, 92, 36), (255, 206, 74), None),
    "water": ((58, 124, 210), (206, 234, 255), None),
    "electric": ((232, 196, 52), (58, 58, 72), None),
    "grass": ((84, 160, 66), (168, 216, 106), None),
    "ice": ((140, 214, 232), (238, 252, 255), None),
    "fighting": ((166, 56, 44), (240, 208, 160), None),
    "poison": ((134, 64, 168), (216, 154, 230), None),
    "ground": ((176, 130, 76), (230, 205, 138), None),
    "flying": ((122, 166, 230), (242, 247, 255), None),
    "psychic": ((208, 78, 142), (255, 208, 234), None),
    "bug": ((126, 163, 44), (216, 226, 90), None),
    "rock": ((125, 111, 88), (200, 183, 138), None),
    "ghost": ((48, 34, 68), (106, 77, 143), (255, 48, 48)),
    "dragon": ((75, 63, 180), (216, 180, 58), None),
    "dark": ((39, 34, 41), (90, 74, 88), (180, 82, 255)),
    "steel": ((154, 168, 184), (223, 231, 240), None),
}
TYPES = sorted(PALETTE)

# The 4x4 texture grid (8x8 texels per cell). head_front is a 2x2 block (16x16) for the eyes.
# name -> (x, y, w, h) in texels.
CELLS = {
    "body_side": (0, 0, 8, 8),
    "body_top": (8, 0, 8, 8),
    "body_front": (16, 0, 8, 8),
    "body_back": (24, 0, 8, 8),
    "body_bottom": (0, 8, 8, 8),
    "head_front": (8, 8, 16, 16),
    "head_side": (24, 8, 8, 8),
    "limb": (0, 16, 8, 8),
    "head_top": (24, 16, 8, 8),
    "limb_dark": (0, 24, 8, 8),
    "head_bottom": (8, 24, 8, 8),
    "head_back": (16, 24, 8, 8),
    "accent": (24, 24, 8, 8),
}

# Which cell each box face uses, by box role. Faces: +x -x +y -y +z (front) -z (back).
ROLE_CELLS = {
    "body": {"+x": "body_side", "-x": "body_side", "+y": "body_top", "-y": "body_bottom",
             "+z": "body_front", "-z": "body_back"},
    "head": {"+x": "head_side", "-x": "head_side", "+y": "head_top", "-y": "head_bottom",
             "+z": "head_front", "-z": "head_back"},
    "limb": {"+x": "limb", "-x": "limb", "+y": "limb_dark", "-y": "limb_dark",
             "+z": "limb", "-z": "limb_dark"},
    "accent": {"+x": "accent", "-x": "accent", "+y": "accent", "-y": "limb_dark",
               "+z": "accent", "-z": "accent"},
    "dark": {"+x": "limb_dark", "-x": "limb_dark", "+y": "limb_dark", "-y": "limb_dark",
             "+z": "limb_dark", "-z": "limb_dark"},
}

# Face geometry: outward normal, and corners in the order bottom-left, bottom-right, top-right,
# top-left as seen from outside the box (so the UV layout is never mirrored).
FACES = {
    "+z": ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    "-z": ((0, 0, -1), [(1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)]),
    "+x": ((1, 0, 0), [(1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1)]),
    "-x": ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    "+y": ((0, 1, 0), [(0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)]),
    "-y": ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
}


# ---------------------------------------------------------------- small helpers

def clamp8(v):
    return max(0, min(255, int(round(v))))


def mix(a, b, t):
    return tuple(clamp8(x + (y - x) * t) for x, y in zip(a, b))


def lighten(c, t):
    return mix(c, (255, 255, 255), t)


def darken(c, t):
    return mix(c, (0, 0, 0), t)


def hue_shift(c, dh):
    r, g, b = (v / 255.0 for v in c)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    r, g, b = colorsys.hls_to_rgb((h + dh) % 1.0, l, s)
    return (clamp8(r * 255), clamp8(g * 255), clamp8(b * 255))


def unit_hash(*parts):
    """Deterministic float in [0, 1) from any printable parts."""
    digest = hashlib.sha256("|".join(str(p) for p in parts).encode("utf-8")).digest()
    return int.from_bytes(digest[:4], "big") / 4294967296.0


def sn(u, ph=0.0):
    return math.sin(TAU * (u + ph))


def env(u):
    """0 at the ends, 1 in the middle: a lunge that goes out and comes back."""
    return math.sin(math.pi * max(0.0, min(1.0, u)))


def smooth(u):
    u = max(0.0, min(1.0, u))
    return 0.5 - 0.5 * math.cos(math.pi * u)


def quat_axis(axis, angle):
    s = math.sin(angle / 2.0)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(angle / 2.0))


def qmul(p, q):
    x1, y1, z1, w1 = p
    x2, y2, z2, w2 = q
    return (w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
            w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
            w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
            w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2)


def quat_euler(rx, ry, rz):
    return qmul(qmul(quat_axis((0, 1, 0), ry), quat_axis((1, 0, 0), rx)), quat_axis((0, 0, 1), rz))


# ---------------------------------------------------------------- textures

def paint_type_texture(type_name, shiny):
    """Returns a 32x32 grid of (r, g, b, a) tuples."""
    base, accent, glow = PALETTE[type_name]
    if shiny:
        base = hue_shift(base, 0.33)
        accent = hue_shift(accent, 0.33)
    cell_colour = {
        "body_side": base,
        "body_top": lighten(base, 0.14),
        "body_front": base,
        "body_back": darken(base, 0.30),
        "body_bottom": mix(base, accent, 0.45),
        "head_side": darken(base, 0.08),
        "head_top": lighten(base, 0.10),
        "head_bottom": darken(base, 0.22),
        "head_back": darken(base, 0.22),
        "limb": darken(base, 0.10),
        "limb_dark": darken(base, 0.45),
        "accent": accent,
        "head_front": lighten(base, 0.06),
    }
    img = [[(0, 0, 0, 255)] * TEX for _ in range(TEX)]
    for name, (x0, y0, w, h) in CELLS.items():
        col = cell_colour[name]
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                n = (unit_hash(type_name, shiny, name, x, y) - 0.5) * 12.0
                img[y][x] = (clamp8(col[0] + n), clamp8(col[1] + n), clamp8(col[2] + n), 255)
    paint_eyes(img, type_name, base, glow, shiny)
    return img


ANGRY_TYPES = ("fire", "fighting", "dragon", "dark")


def paint_eyes(img, type_name, base, glow, shiny):
    """Two expressive eyes, brows and a mouth on the head_front block (local 0..15 coordinates).

    Angry types get slanted brows that drop towards the nose; glowing-eye types get a wide toothy grin.
    """
    ox, oy = CELLS["head_front"][0], CELLS["head_front"][1]
    sclera = (26, 16, 32) if glow else (238, 238, 230)
    iris = glow if glow else (60, 52, 66) if not shiny else (40, 36, 44)
    dark = (14, 10, 16)
    mouth = (40, 22, 26)
    teeth = (236, 232, 220)

    def put(lx, ly, col):
        img[oy + ly][ox + lx] = (col[0], col[1], col[2], 255)

    for ex in (2, 10):  # left eye block x 2..5, right eye mirrored at 10..13
        for y in range(5, 10):
            for x in range(ex, ex + 4):
                put(x, y, sclera)
        for y in range(6, 10):
            for x in range(ex + 1, ex + 4):
                put(x, y, iris)
        for y in range(7, 9):
            for x in range(ex + 2, ex + 4):
                put(x, y, dark)
        put(ex + 1, 6, (255, 255, 255))
    if type_name in ANGRY_TYPES:
        for x, y in ((2, 3), (3, 3), (4, 4), (5, 4), (13, 3), (12, 3), (11, 4), (10, 4)):
            put(x, y, dark)
    if glow:
        for x in range(4, 12):
            put(x, 12, mouth)
        for x in (3, 12):
            put(x, 11, mouth)
        for x in (6, 9):
            put(x, 12, teeth)
    else:
        for x in range(6, 10):
            put(x, 12, mouth)
        put(5, 11, mouth)
        put(10, 11, mouth)


def write_png(path, img):
    height = len(img)
    width = len(img[0])
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in img)

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(blob)


# ---------------------------------------------------------------- rigs

class Rig:
    """A skeleton of joints (pivots in node units) and boxes (in bind pose, node units)."""

    def __init__(self):
        self.joints = []
        self.index = {}
        self.boxes = []

    def joint(self, name, parent, pivot):
        self.index[name] = len(self.joints)
        self.joints.append({"name": name, "parent": self.index[parent] if parent else -1,
                            "pivot": tuple(pivot)})

    def box(self, joint, lo, hi, role, front=None):
        cells = dict(ROLE_CELLS[role])
        if front:
            cells["+z"] = front
        self.boxes.append({"joint": self.index[joint], "lo": tuple(lo), "hi": tuple(hi), "cells": cells})


def biped_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("body", "root", (0, 0.36, 0))
    r.joint("head", "body", (0, 0.70, 0))
    r.joint("arm_l", "body", (-0.22, 0.68, 0))
    r.joint("arm_r", "body", (0.22, 0.68, 0))
    r.joint("leg_l", "root", (-0.10, 0.36, 0))
    r.joint("leg_r", "root", (0.10, 0.36, 0))
    r.box("body", (-0.18, 0.36, -0.11), (0.18, 0.70, 0.11), "body")
    r.box("head", (-0.16, 0.70, -0.16), (0.16, 1.00, 0.16), "head")
    r.box("head", (-0.03, 1.00, -0.03), (0.03, 1.10, 0.03), "accent")
    r.box("arm_l", (-0.30, 0.36, -0.06), (-0.18, 0.68, 0.06), "limb")
    r.box("arm_r", (0.18, 0.36, -0.06), (0.30, 0.68, 0.06), "limb")
    r.box("leg_l", (-0.18, 0.0, -0.07), (-0.02, 0.36, 0.07), "limb")
    r.box("leg_r", (0.02, 0.0, -0.07), (0.18, 0.36, 0.07), "limb")
    return r


def biped_pose(anim, u):
    p = {}
    if anim == "stand":
        a = sn(u)
        p["body"] = {"s": (1.0 - 0.01 * a, 1.0 + 0.02 * a, 1.0 - 0.01 * a)}
        p["head"] = {"r": (0.03 * a, 0, 0)}
        p["arm_l"] = {"r": (0.05 * a, 0, 0)}
        p["arm_r"] = {"r": (-0.05 * a, 0, 0)}
    elif anim == "walk":
        a = sn(u)
        p["leg_l"] = {"r": (0.55 * a, 0, 0)}
        p["leg_r"] = {"r": (-0.55 * a, 0, 0)}
        p["arm_l"] = {"r": (-0.45 * a, 0, 0)}
        p["arm_r"] = {"r": (0.45 * a, 0, 0)}
        p["body"] = {"t": (0, 0.015 * math.cos(TAU * 2 * u), 0)}
    elif anim == "run":
        a = sn(2 * u)
        p["leg_l"] = {"r": (0.95 * a, 0, 0)}
        p["leg_r"] = {"r": (-0.95 * a, 0, 0)}
        p["arm_l"] = {"r": (-0.85 * a, 0, 0)}
        p["arm_r"] = {"r": (0.85 * a, 0, 0)}
        p["body"] = {"r": (0.18, 0, 0), "t": (0, 0.03 * math.cos(TAU * 4 * u), 0)}
    elif anim == "punch":
        e = env(u)
        p["arm_r"] = {"r": (-1.35 * e, 0, 0)}
        p["body"] = {"t": (0, 0, 0.08 * e)}
        p["head"] = {"r": (0.2 * e, 0, 0)}
    elif anim == "die":
        s = smooth(u)
        p["body"] = {"r": (0, 0, 1.45 * s)}
        p["leg_l"] = {"r": (0.5 * s, 0, 0)}
        p["arm_l"] = {"r": (0, 0, 0.6 * s)}
    elif anim == "sit":
        s = smooth(u)
        p["body"] = {"t": (0, -0.14 * s, 0), "r": (0.25 * s, 0, 0)}
        p["leg_l"] = {"r": (-1.2 * s, 0, 0)}
        p["leg_r"] = {"r": (-1.2 * s, 0, 0)}
        p["head"] = {"r": (0.3 * s, 0, 0)}
    return p


def quadruped_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("body", "root", (0, 0.42, 0))
    r.joint("head", "body", (0, 0.50, 0.28))
    r.joint("tail", "body", (0, 0.46, -0.32))
    r.joint("lf", "root", (-0.14, 0.36, 0.22))
    r.joint("rf", "root", (0.14, 0.36, 0.22))
    r.joint("lb", "root", (-0.14, 0.36, -0.22))
    r.joint("rb", "root", (0.14, 0.36, -0.22))
    r.box("body", (-0.20, 0.30, -0.32), (0.20, 0.52, 0.30), "body")
    r.box("head", (-0.15, 0.40, 0.28), (0.15, 0.66, 0.52), "head")
    r.box("tail", (-0.04, 0.46, -0.52), (0.04, 0.60, -0.30), "accent")
    for name, x, z in (("lf", -0.14, 0.22), ("rf", 0.14, 0.22), ("lb", -0.14, -0.22), ("rb", 0.14, -0.22)):
        r.box(name, (x - 0.05, 0.0, z - 0.05), (x + 0.05, 0.36, z + 0.05), "limb")
    return r


def quadruped_pose(anim, u):
    p = {}
    if anim == "stand":
        a = sn(u)
        p["body"] = {"s": (1.0, 1.0 + 0.02 * a, 1.0)}
        p["tail"] = {"r": (0, 0.35 * sn(u), 0)}
        p["head"] = {"r": (0.04 * a, 0, 0)}
    elif anim in ("walk", "run"):
        cycles = 1 if anim == "walk" else 2
        amp = 0.45 if anim == "walk" else 0.85
        a = sn(cycles * u)
        p["lf"] = {"r": (amp * a, 0, 0)}
        p["rb"] = {"r": (amp * a, 0, 0)}
        p["rf"] = {"r": (-amp * a, 0, 0)}
        p["lb"] = {"r": (-amp * a, 0, 0)}
        p["body"] = {"t": (0, 0.012 * math.cos(TAU * 2 * cycles * u), 0)}
        p["tail"] = {"r": (0, 0.4 * sn(cycles * u), 0)}
    elif anim == "punch":
        e = env(u)
        p["head"] = {"t": (0, 0, 0.12 * e), "r": (0.45 * e, 0, 0)}
        p["tail"] = {"r": (0, 0.5 * e, 0)}
    elif anim == "die":
        s = smooth(u)
        p["body"] = {"r": (0, 0, 1.5 * s)}
        p["lf"] = {"r": (0.8 * s, 0, 0)}
        p["rf"] = {"r": (0.8 * s, 0, 0)}
        p["head"] = {"r": (0.3 * s, 0, 0)}
    elif anim == "sit":
        s = smooth(u)
        p["body"] = {"t": (0, -0.14 * s, 0), "r": (-0.15 * s, 0, 0)}
        p["head"] = {"r": (0.5 * s, 0, 0)}
        p["lf"] = {"r": (-0.6 * s, 0, 0)}
        p["rf"] = {"r": (-0.6 * s, 0, 0)}
    return p


def serpent_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    segs = [-0.60, -0.39, -0.18, 0.03]
    parent = "root"
    for i, z in enumerate(segs):
        name = "seg%d" % i
        r.joint(name, parent, (0, 0.10, z))
        r.box(name, (-0.09, 0.0, z), (0.09, 0.20, z + 0.21), "body")
        parent = name
    r.joint("head", parent, (0, 0.12, 0.24))
    r.box("head", (-0.12, 0.0, 0.24), (0.12, 0.26, 0.46), "head")
    r.box("head", (-0.02, 0.26, 0.30), (0.02, 0.34, 0.40), "accent")
    return r


def serpent_pose(anim, u):
    p = {}
    if anim in ("stand", "walk", "run"):
        amp, cycles = {"stand": (0.08, 1), "walk": (0.35, 1), "run": (0.5, 2)}[anim]
        for i in range(4):
            p["seg%d" % i] = {"r": (0, amp * sn(cycles * u, -i * 0.12), 0)}
        p["head"] = {"r": (0, 0.8 * amp * sn(cycles * u, -0.5), 0)}
    elif anim == "punch":
        e = env(u)
        p["head"] = {"t": (0, 0, 0.14 * e), "r": (0.3 * e, 0, 0)}
    elif anim == "die":
        s = smooth(u)
        p["root"] = {"r": (0, 0, 1.5 * s)}
    elif anim == "sit":
        s = smooth(u)
        p["head"] = {"r": (0.5 * s, 0, 0)}
        for i in range(4):
            p["seg%d" % i] = {"s": (1.0, 1.0 - 0.3 * s, 1.0)}
    return p


def avian_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("body", "root", (0, 0.42, 0))
    r.joint("head", "body", (0, 0.56, 0.12))
    r.joint("wing_l", "body", (-0.13, 0.52, -0.02))
    r.joint("wing_r", "body", (0.13, 0.52, -0.02))
    r.joint("leg_l", "root", (-0.06, 0.30, 0))
    r.joint("leg_r", "root", (0.06, 0.30, 0))
    r.joint("tail", "body", (0, 0.36, -0.16))
    r.box("body", (-0.13, 0.30, -0.16), (0.13, 0.56, 0.14), "body")
    r.box("head", (-0.11, 0.56, 0.02), (0.11, 0.80, 0.24), "head")
    r.box("head", (-0.04, 0.62, 0.24), (0.04, 0.70, 0.34), "dark")
    r.box("wing_l", (-0.40, 0.30, -0.10), (-0.13, 0.50, 0.06), "accent")
    r.box("wing_r", (0.13, 0.30, -0.10), (0.40, 0.50, 0.06), "accent")
    r.box("leg_l", (-0.09, 0.0, -0.02), (-0.03, 0.30, 0.04), "limb")
    r.box("leg_r", (0.03, 0.0, -0.02), (0.09, 0.30, 0.04), "limb")
    r.box("tail", (-0.09, 0.30, -0.36), (0.09, 0.42, -0.14), "accent")
    return r


def avian_pose(anim, u):
    p = {}
    if anim == "stand":
        a = sn(u)
        p["wing_l"] = {"r": (0, 0, -0.05 + 0.03 * a)}
        p["wing_r"] = {"r": (0, 0, 0.05 - 0.03 * a)}
        p["head"] = {"r": (0.05 * a, 0, 0)}
    elif anim == "walk":
        a = sn(u)
        p["leg_l"] = {"r": (0.4 * a, 0, 0)}
        p["leg_r"] = {"r": (-0.4 * a, 0, 0)}
        p["wing_l"] = {"r": (0, 0, 0.2 * a)}
        p["wing_r"] = {"r": (0, 0, -0.2 * a)}
        p["body"] = {"r": (0.08, 0, 0)}
    elif anim == "run":
        a = sn(2 * u)
        p["leg_l"] = {"r": (0.8 * a, 0, 0)}
        p["leg_r"] = {"r": (-0.8 * a, 0, 0)}
        p["wing_l"] = {"r": (0, 0, 0.6 * a)}
        p["wing_r"] = {"r": (0, 0, -0.6 * a)}
        p["body"] = {"r": (0.18, 0, 0)}
    elif anim == "punch":
        e = env(u)
        p["head"] = {"r": (0.7 * e, 0, 0)}
        p["body"] = {"t": (0, 0, 0.06 * e)}
    elif anim == "die":
        s = smooth(u)
        p["root"] = {"r": (0, 0, 1.5 * s)}
        p["wing_l"] = {"r": (0, 0, 0.8 * s)}
        p["wing_r"] = {"r": (0, 0, -0.8 * s)}
    elif anim == "sit":
        s = smooth(u)
        p["body"] = {"t": (0, -0.14 * s, 0), "r": (0.5 * s, 0, 0)}
        p["wing_l"] = {"r": (0, 0, -0.4 * s)}
        p["wing_r"] = {"r": (0, 0, 0.4 * s)}
    return p


def blob_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("body", "root", (0, 0, 0))
    r.box("body", (-0.34, 0.0, -0.34), (0.34, 0.66, 0.34), "body", front="head_front")
    r.box("body", (-0.22, 0.66, -0.22), (0.22, 0.70, 0.22), "accent")
    return r


def blob_pose(anim, u):
    p = {}
    if anim == "stand":
        a = sn(u)
        p["body"] = {"s": (1.0 + 0.03 * a, 1.0 - 0.03 * a, 1.0 + 0.03 * a)}
    elif anim in ("walk", "run"):
        cycles = 1 if anim == "walk" else 2
        height = 0.14 if anim == "walk" else 0.22
        a = sn(cycles * u)
        p["root"] = {"t": (0, height * abs(math.sin(math.pi * cycles * u)), 0)}
        p["body"] = {"s": (1.0 + 0.06 * a, 1.0 - 0.06 * a, 1.0 + 0.06 * a)}
    elif anim == "punch":
        e = env(u)
        p["body"] = {"t": (0, 0, 0.14 * e), "s": (1.0 + 0.1 * e, 1.0 - 0.15 * e, 1.0 + 0.05 * e)}
    elif anim == "die":
        s = smooth(u)
        p["body"] = {"s": (1.0 + 0.45 * s, 1.0 - 0.7 * s, 1.0 + 0.45 * s)}
    elif anim == "sit":
        s = smooth(u)
        p["body"] = {"s": (1.0 + 0.2 * s, 1.0 - 0.4 * s, 1.0 + 0.2 * s)}
    return p


def insect_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("thorax", "root", (0, 0.16, 0.02))
    r.joint("head", "thorax", (0, 0.20, 0.20))
    r.joint("abdomen", "thorax", (0, 0.16, -0.10))
    r.joint("ant_l", "head", (-0.04, 0.28, 0.28))
    r.joint("ant_r", "head", (0.04, 0.28, 0.28))
    legs = []
    for side, sx in (("l", -1), ("r", 1)):
        for k, z in enumerate((0.06, -0.02, -0.10)):
            name = "leg_%s%d" % (side, k)
            r.joint(name, "thorax", (sx * 0.12, 0.10, z))
            legs.append((name, k, sx))
    r.box("thorax", (-0.12, 0.08, -0.10), (0.12, 0.26, 0.10), "body")
    r.box("head", (-0.10, 0.12, 0.12), (0.10, 0.28, 0.30), "head")
    r.box("abdomen", (-0.15, 0.06, -0.40), (0.15, 0.24, -0.10), "body")
    r.box("ant_l", (-0.07, 0.28, 0.25), (-0.03, 0.44, 0.29), "dark")
    r.box("ant_r", (0.03, 0.28, 0.25), (0.07, 0.44, 0.29), "dark")
    for name, k, sx in legs:
        z = (0.06, -0.02, -0.10)[k]
        x0, x1 = (-0.26, -0.10) if sx < 0 else (0.10, 0.26)
        r.box(name, (x0, 0.0, z - 0.02), (x1, 0.10, z + 0.02), "limb")
    return r


def insect_pose(anim, u):
    p = {}
    groups = {"A": ["leg_l0", "leg_l2", "leg_r1"], "B": ["leg_r0", "leg_r2", "leg_l1"]}
    if anim in ("stand", "walk", "run"):
        if anim == "stand":
            p["ant_l"] = {"r": (0.12 * sn(u), 0, 0)}
            p["ant_r"] = {"r": (-0.12 * sn(u), 0, 0)}
        else:
            cycles = 1 if anim == "walk" else 2
            amp = 0.35 if anim == "walk" else 0.55
            for phase, names in ((0.0, groups["A"]), (0.5, groups["B"])):
                for name in names:
                    sign = -1.0 if name.startswith("leg_l") else 1.0
                    p[name] = {"r": (0, 0, sign * amp * sn(cycles * u, phase))}
    elif anim == "punch":
        e = env(u)
        p["head"] = {"t": (0, 0, 0.10 * e)}
        p["abdomen"] = {"r": (0.2 * e, 0, 0)}
    elif anim == "die":
        s = smooth(u)
        p["root"] = {"r": (0, 0, math.pi * s)}
        for name in ("leg_l0", "leg_r0", "leg_l2", "leg_r2"):
            p[name] = {"r": (0, 0, 0.4 * s)}
    elif anim == "sit":
        s = smooth(u)
        p["thorax"] = {"s": (1.0, 1.0 - 0.25 * s, 1.0)}
        for side in ("l", "r"):
            for k in range(3):
                sign = -1.0 if side == "l" else 1.0
                p["leg_%s%d" % (side, k)] = {"r": (0, 0, sign * 0.6 * s)}
    return p


def fish_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("body", "root", (0, 0.2, 0))
    r.joint("tail", "body", (0, 0.2, -0.30))
    r.joint("fin_l", "body", (-0.12, 0.20, 0.10))
    r.joint("fin_r", "body", (0.12, 0.20, 0.10))
    r.box("body", (-0.12, 0.04, -0.30), (0.12, 0.36, 0.30), "body", front="head_front")
    r.box("tail", (-0.02, 0.0, -0.50), (0.02, 0.40, -0.28), "accent")
    r.box("body", (-0.01, 0.36, -0.12), (0.01, 0.48, 0.12), "accent")
    r.box("fin_l", (-0.26, 0.14, 0.04), (-0.12, 0.18, 0.16), "accent")
    r.box("fin_r", (0.12, 0.14, 0.04), (0.26, 0.18, 0.16), "accent")
    return r


def fish_pose(anim, u):
    p = {}
    if anim in ("stand", "walk", "run"):
        cycles, amp = {"stand": (1, 0.25), "walk": (1, 0.6), "run": (2, 0.9)}[anim]
        a = sn(cycles * u)
        p["tail"] = {"r": (0, amp * a, 0)}
        p["body"] = {"r": (0, 0.12 * a, 0)}
    elif anim == "punch":
        e = env(u)
        p["body"] = {"t": (0, 0, 0.12 * e)}
        p["tail"] = {"r": (0, 0.6 * e, 0)}
    elif anim == "die":
        s = smooth(u)
        p["root"] = {"r": (0, 0, 1.35 * s), "t": (0, -0.04 * s, 0)}
    elif anim == "sit":
        s = smooth(u)
        p["fin_l"] = {"r": (0, 0, -0.7 * s)}
        p["fin_r"] = {"r": (0, 0, 0.7 * s)}
        p["body"] = {"t": (0, -0.03 * s, 0)}
    return p


def other_rig():
    r = Rig()
    r.joint("root", None, (0, 0, 0))
    r.joint("body", "root", (0, 0.62, 0))
    xs = (-0.16, -0.05, 0.05, 0.16)
    for i, x in enumerate(xs):
        r.joint("tendril%d" % i, "body", (x, 0.50, 0.0))
        r.box("tendril%d" % i, (x - 0.04, 0.08, -0.02), (x + 0.04, 0.50, 0.02), "dark")
    r.box("body", (-0.22, 0.50, -0.18), (0.22, 0.92, 0.18), "body", front="head_front")
    r.box("body", (-0.08, 0.92, -0.08), (0.08, 1.0, 0.08), "accent")
    return r


def other_pose(anim, u):
    p = {}
    if anim in ("stand", "walk", "run"):
        cycles, amp = {"stand": (1, 0.15), "walk": (1, 0.35), "run": (2, 0.5)}[anim]
        p["root"] = {"t": (0, 0.03 * sn(cycles * u), 0)}
        for i in range(4):
            ph = i * 0.25
            p["tendril%d" % i] = {"r": (amp * sn(cycles * u, ph), 0, 0.5 * amp * sn(cycles * u, ph + 0.25))}
    elif anim == "punch":
        e = env(u)
        p["root"] = {"t": (0, 0, 0.14 * e)}
    elif anim == "die":
        s = smooth(u)
        p["root"] = {"t": (0, -0.4 * s, 0)}
        p["body"] = {"r": (0, 0, 0.6 * s)}
    elif anim == "sit":
        s = smooth(u)
        p["root"] = {"t": (0, -0.2 * s, 0)}
        for i in range(4):
            p["tendril%d" % i] = {"r": (0.4 * s, 0, 0)}
    return p


RIGS = {
    "biped": (biped_rig, biped_pose),
    "quadruped": (quadruped_rig, quadruped_pose),
    "serpent": (serpent_rig, serpent_pose),
    "avian": (avian_rig, avian_pose),
    "blob": (blob_rig, blob_pose),
    "insect": (insect_rig, insect_pose),
    "fish": (fish_rig, fish_pose),
    "other": (other_rig, other_pose),
}

# name, first frame, last frame, loops
CLIPS = [
    ("stand", 0, 20, True),
    ("walk", 21, 41, True),
    ("run", 42, 52, True),
    ("punch", 53, 63, False),
    ("die", 64, 74, False),
    ("sit", 75, 85, False),
]


# ---------------------------------------------------------------- glTF writer

class BinBuilder:
    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accessors = []

    def _align(self):
        while len(self.data) % 4:
            self.data.append(0)

    def add(self, raw, count, acc_type, component, minmax=None):
        self._align()
        offset = len(self.data)
        self.data += raw
        self.views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw)})
        acc = {"bufferView": len(self.views) - 1, "componentType": component, "count": count,
               "type": acc_type}
        if minmax is not None:
            acc["min"], acc["max"] = minmax
        self.accessors.append(acc)
        return len(self.accessors) - 1


FLOAT = 5126
USHORT = 5123


def pack_floats(values):
    flat = [v for item in values for v in (item if isinstance(item, (tuple, list)) else (item,))]
    return struct.pack("<%df" % len(flat), *flat)


def pack_ushorts(values):
    flat = [v for item in values for v in (item if isinstance(item, (tuple, list)) else (item,))]
    return struct.pack("<%dH" % len(flat), *flat)


def build_mesh(rig, binb):
    positions, normals, uvs, joints, weights, indices = [], [], [], [], [], []
    for box in rig.boxes:
        lo, hi = box["lo"], box["hi"]
        for face, (normal, corners) in FACES.items():
            cell = CELLS[box["cells"][face]]
            x0, y0, w, h = cell
            u0 = (x0 + 0.5) / TEX
            u1 = (x0 + w - 0.5) / TEX
            v0 = (y0 + 0.5) / TEX
            v1 = (y0 + h - 0.5) / TEX
            uv_corners = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]  # BL, BR, TR, TL
            verts = []
            for cx, cy, cz in corners:
                px = lo[0] if cx == 0 else hi[0]
                py = lo[1] if cy == 0 else hi[1]
                pz = lo[2] if cz == 0 else hi[2]
                verts.append((px, py, pz))
            # Winding: counter-clockwise seen from outside, so the triangle normal matches the face.
            a, b, c = verts[0], verts[1], verts[2]
            ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            bc = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            cross = (ab[1] * bc[2] - ab[2] * bc[1], ab[2] * bc[0] - ab[0] * bc[2],
                     ab[0] * bc[1] - ab[1] * bc[0])
            ccw = sum(cross[i] * normal[i] for i in range(3)) > 0
            base = len(positions)
            for vi in range(4):
                px, py, pz = verts[vi]
                positions.append(tuple(v * UNITS for v in (px, py, pz)))
                normals.append(normal)
                uvs.append(uv_corners[vi])
                joints.append((box["joint"], 0, 0, 0))
                weights.append((1.0, 0.0, 0.0, 0.0))
            if ccw:
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            else:
                indices += [base, base + 2, base + 1, base, base + 3, base + 2]

    n = len(positions)
    pmin = [min(p[i] for p in positions) for i in range(3)]
    pmax = [max(p[i] for p in positions) for i in range(3)]
    acc_pos = binb.add(pack_floats(positions), n, "VEC3", FLOAT, (pmin, pmax))
    acc_nrm = binb.add(pack_floats(normals), n, "VEC3", FLOAT)
    acc_uv = binb.add(pack_floats(uvs), n, "VEC2", FLOAT)
    acc_jnt = binb.add(pack_ushorts(joints), n, "VEC4", USHORT)
    acc_wgt = binb.add(pack_floats(weights), n, "VEC4", FLOAT)
    acc_idx = binb.add(pack_ushorts(indices), len(indices), "SCALAR", USHORT)
    return {"primitives": [{"attributes": {"POSITION": acc_pos, "NORMAL": acc_nrm, "TEXCOORD_0": acc_uv,
                                           "JOINTS_0": acc_jnt, "WEIGHTS_0": acc_wgt},
                            "indices": acc_idx}]}


def bind_local(rig, j):
    joint = rig.joints[j]
    pivot = joint["pivot"]
    if joint["parent"] < 0:
        parent = (0.0, 0.0, 0.0)
    else:
        parent = rig.joints[joint["parent"]]["pivot"]
    return tuple((pivot[i] - parent[i]) * UNITS for i in range(3))


def build_animation(rig, pose_fn, binb):
    """One clip covering every frame range. Returns the glTF animation dict."""
    times = []
    poses = []
    for name, first, last, _loops in CLIPS:
        for k in range(SAMPLES + 1):
            u = k / float(SAMPLES)
            times.append(float(first + (last - first) * u))
            poses.append(pose_fn(name, u))
    for a, b in zip(times, times[1:]):
        if not b > a:
            raise ValueError("keyframe times must increase")
    acc_time = binb.add(pack_floats(times), len(times), "SCALAR", FLOAT, ([times[0]], [times[-1]]))

    samplers, channels = [], []
    for j, joint in enumerate(rig.joints):
        trans, rots, scales = [], [], []
        for pose in poses:
            entry = pose.get(joint["name"], {})
            t = entry.get("t", (0.0, 0.0, 0.0))
            r = entry.get("r", (0.0, 0.0, 0.0))
            s = entry.get("s", (1.0, 1.0, 1.0))
            bl = bind_local(rig, j)
            trans.append(tuple(bl[i] + t[i] * UNITS for i in range(3)))
            rots.append(quat_euler(*r))
            scales.append(tuple(s))
        outs = [
            ("translation", binb.add(pack_floats(trans), len(trans), "VEC3", FLOAT)),
            ("rotation", binb.add(pack_floats(rots), len(rots), "VEC4", FLOAT)),
            ("scale", binb.add(pack_floats(scales), len(scales), "VEC3", FLOAT)),
        ]
        for path, acc_out in outs:
            samplers.append({"input": acc_time, "output": acc_out, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": path}})
    return {"name": "minemon_standin", "channels": channels, "samplers": samplers}


def build_glb(plan):
    rig_fn, pose_fn = RIGS[plan]
    rig = rig_fn()
    binb = BinBuilder()
    mesh = build_mesh(rig, binb)

    # Inverse bind matrices: bind pose is pure translation, so each is a translation by -pivot (column-major).
    ibm = []
    for joint in rig.joints:
        px, py, pz = (v * UNITS for v in joint["pivot"])
        ibm.append((1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -px, -py, -pz, 1.0))
    acc_ibm = binb.add(pack_floats(ibm), len(ibm), "MAT4", FLOAT)

    anim = build_animation(rig, pose_fn, binb)

    nodes = []
    for j, joint in enumerate(rig.joints):
        children = [k for k, other in enumerate(rig.joints) if other["parent"] == j]
        node = {"name": joint["name"], "translation": list(bind_local(rig, j))}
        if children:
            node["children"] = children
        nodes.append(node)
    mesh_node = len(nodes)
    nodes.append({"name": "mesh", "mesh": 0, "skin": 0})

    gltf = {
        "asset": {"version": "2.0", "generator": "minemon tools/gen_standins.py (T-18)"},
        "scene": 0,
        "scenes": [{"nodes": [0, mesh_node]}],
        "nodes": nodes,
        "meshes": [mesh],
        "skins": [{"name": "skeleton", "joints": list(range(len(rig.joints))), "skeleton": 0,
                   "inverseBindMatrices": acc_ibm}],
        "animations": [anim],
        "accessors": binb.accessors,
        "bufferViews": binb.views,
        "buffers": [{"byteLength": len(binb.data)}],
    }
    json_bytes = json.dumps(gltf, separators=(",", ":"), sort_keys=True).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = bytes(binb.data)
    bin_bytes += b"\x00" * ((4 - len(bin_bytes) % 4) % 4)

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    out += struct.pack("<II", len(bin_bytes), 0x004E4942) + bin_bytes
    return out


# ---------------------------------------------------------------- main

def write_all(model_dir=MODEL_DIR, tex_dir=TEX_DIR):
    os.makedirs(model_dir, exist_ok=True)
    os.makedirs(tex_dir, exist_ok=True)
    written = []
    for plan in PLANS:
        path = os.path.join(model_dir, "mm_%s.glb" % plan)
        with open(path, "wb") as f:
            f.write(build_glb(plan))
        written.append(path)
    for type_name in TYPES:
        for shiny in (False, True):
            suffix = "_shiny" if shiny else ""
            path = os.path.join(tex_dir, "mm_type_%s%s.png" % (type_name, suffix))
            write_png(path, paint_type_texture(type_name, shiny))
            written.append(path)
    return written


def main():
    paths = write_all()
    print("gen_standins: wrote %d files under %s" % (len(paths), MEDIA_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
