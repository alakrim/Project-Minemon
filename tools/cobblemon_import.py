#!/usr/bin/env python3
"""Cobblemon Bedrock models to Luanti glTF (T-25a; owner directive D-029).

Reads a clone of kirbycope/cobblemon-bedrock (pinned in scripts/versions.env) and writes a generated pack mod.
The output is never committed: it goes to .tools/pack_cobblemon, which is git-ignored.

  <out>/minemon_pack_cobblemon/mod.conf
  <out>/minemon_pack_cobblemon/init.lua         minemon_pack.models[dex] = {mesh, texture, texture_shiny, height, width}
  <out>/minemon_pack_cobblemon/CREDITS.txt
  <out>/minemon_pack_cobblemon/models/mmp_NNNN.glb       rest pose, one skinned mesh, one joint per Bedrock bone
  <out>/minemon_pack_cobblemon/textures/mmp_NNNN.png     the Bedrock texture, copied
  <out>/minemon_pack_cobblemon/textures/mmp_NNNN_s.png   the shiny texture (the base texture when none ships)

Rules:
  - 16 px = 1 block = 1 node = 10 glTF units (as tools/gen_standins.py).
  - The lowest point of each model (its feet) sits at y = 0, found per model; the Bedrock ground plane is not used.
    The front faces the same way as the stand-ins of tools/gen_standins.py: the Bedrock front (-z) becomes
    glTF +z (a 180-degree turn about x; see FLIP_ROT).
  - Bones keep their names. A bone's rest pose is its pivot and rotation (degrees, Java/Bedrock order Rz*Ry*Rx).
  - Cube rotation, inflate, mirror and both UV forms (box and per face) are applied; the UV is normalised by the
    geometry's texture_width and texture_height.
  - Animation (T-25b): each .glb carries ONE clip, the same six frame ranges as tools/gen_standins.py
    (stand 0-20, walk 21-41, run 42-52, punch 53-63, die 64-74, sit 75-85). Frames are glTF seconds at speed 1.0.
    Each frame is one keyframe. Bedrock clips are baked with the `molang` package (the permitted dev dependency),
    as deltas on the rest pose. Bedrock's trigonometry is in degrees, and unknown queries read as 0.
    The node rest transforms hold the stand clip's frame 0, so a frozen model looks posed. Feet are grounded in
    that frame. Metadata (anims, scale_hint) goes into the pack's init.lua.

Stdlib, plus `molang` for the animation bake. The GLB writer and the struct helpers come from tools/gen_standins.py.

Usage: python3 tools/cobblemon_import.py --src .tools/cobblemon-bedrock --out .tools/pack_cobblemon [--only 19,25]
           [--species mods/minemon/minemon_core/data/species.json]
Exit: 0 when the run converts what it was asked to (and at least 240 species in a full run), 1 otherwise.
"""

import argparse
import bisect
import collections
import json
import math
import os
import random
import re
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import gen_standins as gs  # noqa: E402  (the stdlib GLB writer; see module docstring)

PACK_NAME = "minemon_pack_cobblemon"
SOURCE_SUBDIR = os.path.join("development_resource_packs", "cobblemon")
DEFAULT_SPECIES = os.path.join(ROOT, "mods", "minemon", "minemon_core", "data", "species.json")
DEX_MAX = 251
FULL_RUN_MIN = 240
PX_PER_BLOCK = 16.0
SCALE = gs.UNITS / PX_PER_BLOCK  # glTF units per pixel

# A rigid transform is a pair (quat, translation in pixels): p -> rot(quat, p) + translation.
# Quaternions are (x, y, z, w).
IDENTITY_Q = (0.0, 0.0, 0.0, 1.0)
IDENTITY = (IDENTITY_Q, (0.0, 0.0, 0.0))
# Model space to glTF space is a 180-degree turn about x (y and z negated) followed by a lift: the lowest point of
# the model goes to y = 0 (see build_model). The lift is the translation part of the root transform.
# The Bedrock front (-z) becomes glTF +z, the front of gen_standins.py; Luanti shows that as facing -z
# (checked on Rattata and Gastly: the face toward a camera at -z when yaw is 0).
FLIP_ROT = (1.0, 0.0, 0.0, 0.0)


# ---------------------------------------------------------------- quaternions and rigid transforms

def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def q_conj(q):
    return (-q[0], -q[1], -q[2], q[3])


def q_rot(q, v):
    """Rotates vector v by unit quaternion q."""
    r = q_mul(q_mul(q, (v[0], v[1], v[2], 0.0)), q_conj(q))
    return (r[0], r[1], r[2])


def q_axis(axis, degrees):
    half = math.radians(degrees) / 2.0
    s = math.sin(half)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(half))


def q_euler(rot):
    """Bedrock bone or cube rotation in degrees [x, y, z]: R = Rz * Ry * Rx, so x is applied first."""
    rx, ry, rz = rot
    return q_mul(q_axis((0.0, 0.0, 1.0), rz), q_mul(q_axis((0.0, 1.0, 0.0), ry), q_axis((1.0, 0.0, 0.0), rx)))


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def neg(a):
    return (-a[0], -a[1], -a[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def t_mul(a, b):
    """a after b: p -> a(b(p))."""
    return (q_mul(a[0], b[0]), add(q_rot(a[0], b[1]), a[1]))


def t_inv(a):
    q = q_conj(a[0])
    return (q, neg(q_rot(q, a[1])))


def t_apply(a, p):
    return add(q_rot(a[0], p), a[1])


def pivot_rot(q, pivot):
    """Rotation q about the point pivot."""
    return (q, sub(pivot, q_rot(q, pivot)))


def quat_to_matrix(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def column_major(xf):
    """glTF mat4 (16 floats, column-major) of a rigid transform in pixels, with the translation in glTF units."""
    m = quat_to_matrix(xf[0])
    t = [c * SCALE for c in xf[1]]
    cols = []
    for j in range(3):
        cols += [m[0][j], m[1][j], m[2][j], 0.0]
    cols += [t[0], t[1], t[2], 1.0]
    return cols


# ---------------------------------------------------------------- box geometry and UV

# Outward normal and image-up direction of each face, in Bedrock space. Bedrock y runs down, so up is -y.
# north is the front (-z). The image-right direction of a face is cross(image-up, view direction).
FACE_NORMAL = {"north": (0, 0, -1), "south": (0, 0, 1), "east": (1, 0, 0), "west": (-1, 0, 0),
               "up": (0, -1, 0), "down": (0, 1, 0)}
FACE_UP = {"north": (0, -1, 0), "south": (0, -1, 0), "east": (0, -1, 0), "west": (0, -1, 0),
           "up": (0, 0, 1), "down": (0, 0, -1)}
FACES = ("north", "south", "east", "west", "up", "down")


def box_uv_rects(u, v, w, h, d):
    """Minecraft box unwrap: each face's texel rectangle (u0, v0, u1, v1), with u0 < u1 and v0 < v1."""
    return {
        "east": (u, v + d, u + d, v + d + h),
        "north": (u + d, v + d, u + d + w, v + d + h),
        "west": (u + d + w, v + d, u + 2 * d + w, v + d + h),
        "south": (u + 2 * d + w, v + d, u + 2 * d + 2 * w, v + d + h),
        "up": (u + d, v, u + d + w, v + d),
        "down": (u + d + w, v, u + d + 2 * w, v + d),
    }


def _axis_of(vec):
    for i, c in enumerate(vec):
        if c:
            return i, (1 if c > 0 else -1)
    raise ValueError("zero vector")


def face_corners(lo, hi, face):
    """The four corners of a box face as (bottom-left, bottom-right, top-right, top-left), seen from outside."""
    normal = FACE_NORMAL[face]
    up = FACE_UP[face]
    right = cross(up, neg(normal))
    plane_axis, plane_sign = _axis_of(normal)
    r_axis, r_sign = _axis_of(right)
    u_axis, u_sign = _axis_of(up)
    plane = hi[plane_axis] if plane_sign > 0 else lo[plane_axis]

    def pick(axis, sign, side):
        # side -1: the minimum along sign * e_axis; side +1: the maximum.
        want_hi = (side > 0) == (sign > 0)
        return hi[axis] if want_hi else lo[axis]

    corners = []
    for side_r, side_u in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        p = [0.0, 0.0, 0.0]
        p[plane_axis] = plane
        p[r_axis] = pick(r_axis, r_sign, side_r)
        p[u_axis] = pick(u_axis, u_sign, side_u)
        corners.append(tuple(p))
    return corners, normal


def face_uv_corners(rect, mirror):
    """Texel (u, v) for BL, BR, TR, TL. A mirror swaps u0 and u1, which flips the texture horizontally."""
    u0, v0, u1, v1 = rect
    if mirror:
        u0, u1 = u1, u0
    return [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]


def cube_faces(cube, bone_mirror):
    """Yields (face, rect, mirror) for the faces a cube draws, from its UV form (box or per face)."""
    uv = cube.get("uv")
    mirror = bool(cube.get("mirror", bone_mirror))
    if isinstance(uv, list):
        u, v = float(uv[0]), float(uv[1])
        size = cube["size"]
        w, h, d = (abs(float(size[0])), abs(float(size[1])), abs(float(size[2])))
        rects = box_uv_rects(u, v, w, h, d)
        for face in FACES:
            yield face, rects[face], mirror
    elif isinstance(uv, dict):
        for face in FACES:
            entry = uv.get(face)
            if not entry or "uv" not in entry:
                continue
            fu, fv = float(entry["uv"][0]), float(entry["uv"][1])
            su, sv = float(entry.get("uv_size", [0, 0])[0]), float(entry.get("uv_size", [0, 0])[1])
            yield face, (fu, fv, fu + su, fv + sv), mirror
    else:
        raise ValueError("cube without uv")


def cube_bounds(cube):
    origin = [float(x) for x in cube["origin"]]
    size = [float(x) for x in cube["size"]]
    inflate = float(cube.get("inflate", 0.0))
    lo = tuple(min(origin[i], origin[i] + size[i]) - inflate for i in range(3))
    hi = tuple(max(origin[i], origin[i] + size[i]) + inflate for i in range(3))
    return lo, hi


# ---------------------------------------------------------------- geometry to a skinned model

def _vec(value, default=(0.0, 0.0, 0.0)):
    if value is None:
        return tuple(default)
    return (float(value[0]), float(value[1]), float(value[2]))


def bone_order(parent):
    """Indices with every parent before its children. Raises on a cycle."""
    n = len(parent)
    done = [False] * n
    order = []
    while len(order) < n:
        progressed = False
        for i in range(n):
            if not done[i] and (parent[i] is None or done[parent[i]]):
                done[i] = True
                order.append(i)
                progressed = True
        if not progressed:
            raise ValueError("bone parent cycle")
    return order


def build_model(geometry, pose=None):
    """The rest-pose model of one Bedrock geometry, with its lowest point at y = 0 (the feet).

    The lowest point is found with a first pass; the Bedrock ground plane (y = 24) is not used, because some
    Cobblemon models (Cyndaquil) stand with their feet well above it. With a pose (Bedrock deltas, see pose_nodes),
    the lowest point is the posed one: the feet are then on the ground in that pose."""
    first = _build_model(geometry, (0.0, 0.0, 0.0))
    if pose is None:
        lowest = min(p[1] for p in first["positions"])
    else:
        lowest = posed_lowest_y(first, pose)
    return _build_model(geometry, (0.0, -lowest, 0.0))


def _build_model(geometry, lift):
    flip = (FLIP_ROT, lift)
    desc = geometry["description"]
    tex_w = float(desc.get("texture_width") or 16)
    tex_h = float(desc.get("texture_height") or 16)
    bones = geometry.get("bones", [])
    if not bones:
        raise ValueError("geometry has no bones")
    names = [b["name"] for b in bones]
    index = {}
    for i, name in enumerate(names):
        if name in index:
            raise ValueError("duplicate bone %s" % name)
        index[name] = i
    parent = [index.get(b.get("parent")) if b.get("parent") is not None else None for b in bones]
    order = bone_order(parent)
    n = len(bones)
    pivots = [_vec(b.get("pivot")) for b in bones]
    rest_deg = [_vec(b.get("rotation")) for b in bones]
    rots = [q_euler(r) for r in rest_deg]

    local = [None] * n  # glTF node transform (pixels), relative to its parent node; top bones include flip
    glob = [None] * n  # the joint's global transform in glTF space at rest (flip included)
    fk = [None] * n  # the rest forward kinematics of the bone in model space (rotations about pivots)
    for i in order:
        p = parent[i]
        if p is None:
            link = (rots[i], pivots[i])
            local[i] = t_mul(flip, link)
            glob[i] = local[i]
            fk[i] = pivot_rot(rots[i], pivots[i])
        else:
            link = (rots[i], sub(pivots[i], pivots[p]))
            local[i] = link
            glob[i] = t_mul(glob[p], link)
            fk[i] = t_mul(fk[p], pivot_rot(rots[i], pivots[i]))

    positions, normals, uvs, joints, weights, indices = [], [], [], [], [], []
    lo_pt = [float("inf")] * 3
    hi_pt = [float("-inf")] * 3
    for i, bone in enumerate(bones):
        bone_mirror = bool(bone.get("mirror", False))
        for cube in bone.get("cubes", []):
            if "rotation" in cube:
                cube_t = pivot_rot(q_euler(_vec(cube["rotation"])), _vec(cube.get("pivot"), pivots[i]))
            else:
                cube_t = IDENTITY
            full = t_mul(flip, t_mul(fk[i], cube_t))
            normal_q = q_mul(flip[0], q_mul(fk[i][0], cube_t[0]))
            lo, hi = cube_bounds(cube)
            for face, rect, mirror in cube_faces(cube, bone_mirror):
                corners, normal = face_corners(lo, hi, face)
                uv = face_uv_corners(rect, mirror)
                base = len(positions)
                for corner, (tu, tv) in zip(corners, uv):
                    p = t_apply(full, corner)
                    for k in range(3):
                        lo_pt[k] = min(lo_pt[k], p[k])
                        hi_pt[k] = max(hi_pt[k], p[k])
                    positions.append(p)
                    normals.append(q_rot(normal_q, normal))
                    uvs.append((tu / tex_w, tv / tex_h))
                    joints.append((i, 0, 0, 0))
                    weights.append((1.0, 0.0, 0.0, 0.0))
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    if not positions:
        raise ValueError("geometry has no cubes")

    inverse_bind = [column_major(t_inv(glob[i])) for i in range(n)]
    children = [[j for j in range(n) if parent[j] == i] for i in range(n)]
    roots = [i for i in range(n) if parent[i] is None]
    return {
        "names": names, "children": children, "roots": roots, "local": local,
        "positions": positions, "normals": normals, "uvs": uvs, "joints": joints, "weights": weights,
        "indices": indices, "inverse_bind": inverse_bind,
        "bounds_px": (tuple(lo_pt), tuple(hi_pt)),
        # what pose_nodes needs to pose the skeleton, and the rest globals that the skin is bound to
        "parent": parent, "order": order, "pivots": pivots, "rest_deg": rest_deg, "flip": flip, "glob": glob,
    }


def pose_nodes(model, pose=None):
    """The glTF node transforms of a posed model: (locals, scales), one per bone, in the order of model["names"].

    pose maps a bone name to {"rotation": degrees [x, y, z], "position": Bedrock pixels [x, y, z] (y up),
    "scale": multipliers}; missing keys are zero (scale one). They are deltas on the rest pose: a bone's rotation is
    its rest Euler angles plus the delta, and its pivot moves by the position delta. A child's translation is its
    animated pivot minus its parent's. With no pose, the locals are model["local"]."""
    pose = pose or {}
    n = len(model["names"])
    parent = model["parent"]
    locals_ = [None] * n
    scales = [(1.0, 1.0, 1.0)] * n
    anchor = [None] * n
    for i in model["order"]:
        delta = pose.get(model["names"][i], {})
        dp = delta.get("position", (0.0, 0.0, 0.0))
        # Bedrock animation y runs up; the geometry's pivots run down (see tools/gen_standins.py and poses.py).
        anchor[i] = add(model["pivots"][i], (float(dp[0]), -float(dp[1]), float(dp[2])))
        rot = q_euler(add(model["rest_deg"][i], delta.get("rotation", (0.0, 0.0, 0.0))))
        p = parent[i]
        if p is None:
            locals_[i] = t_mul(model["flip"], (rot, anchor[i]))
        else:
            locals_[i] = (rot, sub(anchor[i], anchor[p]))
        if "scale" in delta:
            scales[i] = tuple(float(c) for c in delta["scale"])
    return locals_, scales


def chain_globals(model, locals_):
    """The global transform of every bone: its node transform after its parent's."""
    glob = [None] * len(locals_)
    for i in model["order"]:
        p = model["parent"][i]
        glob[i] = locals_[i] if p is None else t_mul(glob[p], locals_[i])
    return glob


def posed_lowest_y(model, pose):
    """The lowest y of the skinned mesh in a pose, in pixels (the skin moves each vertex with its bone)."""
    locals_, _ = pose_nodes(model, pose)
    glob_posed = chain_globals(model, locals_)
    skin = [t_mul(glob_posed[i], t_inv(model["glob"][i])) for i in range(len(locals_))]
    return min(t_apply(skin[j[0]], p)[1] for p, j in zip(model["positions"], model["joints"]))


def write_glb(model, anim):
    """Packs the posed model and its one clip into GLB bytes with the stdlib writer from tools/gen_standins.py.

    The node rest transforms are anim["rest"] (frame 0 of the stand clip); the channels are anim["tracks"]."""
    binb = gs.BinBuilder()
    positions = [tuple(v * SCALE for v in p) for p in model["positions"]]
    n = len(positions)
    pmin = [min(p[k] for p in positions) for k in range(3)]
    pmax = [max(p[k] for p in positions) for k in range(3)]
    acc_pos = binb.add(gs.pack_floats(positions), n, "VEC3", gs.FLOAT, (pmin, pmax))
    acc_nrm = binb.add(gs.pack_floats(model["normals"]), n, "VEC3", gs.FLOAT)
    acc_uv = binb.add(gs.pack_floats(model["uvs"]), n, "VEC2", gs.FLOAT)
    acc_jnt = binb.add(gs.pack_ushorts(model["joints"]), n, "VEC4", gs.USHORT)
    acc_wgt = binb.add(gs.pack_floats(model["weights"]), n, "VEC4", gs.FLOAT)
    if n < 65536:
        idx_raw = struct.pack("<%dH" % len(model["indices"]), *model["indices"])
        idx_type = gs.USHORT
    else:
        idx_raw = struct.pack("<%dI" % len(model["indices"]), *model["indices"])
        idx_type = 5125  # UNSIGNED_INT
    acc_idx = binb.add(idx_raw, len(model["indices"]), "SCALAR", idx_type)
    nb = len(model["names"])
    acc_ibm = binb.add(gs.pack_floats(model["inverse_bind"]), nb, "MAT4", gs.FLOAT)

    rest_locals, rest_scales = anim["rest"]
    nodes = []
    for i, name in enumerate(model["names"]):
        q, t = rest_locals[i]
        node = {"name": name, "translation": [c * SCALE for c in t], "rotation": list(q)}
        if tuple(rest_scales[i]) != (1.0, 1.0, 1.0):
            node["scale"] = list(rest_scales[i])
        if model["children"][i]:
            node["children"] = model["children"][i]
        nodes.append(node)
    mesh_node = len(nodes)
    nodes.append({"name": "mesh", "mesh": 0, "skin": 0})

    gltf = {
        "asset": {"version": "2.0", "generator": "minemon tools/cobblemon_import.py (T-25a, T-25b)"},
        "scene": 0,
        "scenes": [{"nodes": model["roots"] + [mesh_node]}],
        "nodes": nodes,
        "meshes": [{"primitives": [{"attributes": {"POSITION": acc_pos, "NORMAL": acc_nrm, "TEXCOORD_0": acc_uv,
                                                   "JOINTS_0": acc_jnt, "WEIGHTS_0": acc_wgt},
                                    "indices": acc_idx}]}],
        "skins": [{"name": "skeleton", "joints": list(range(nb)), "skeleton": model["roots"][0],
                   "inverseBindMatrices": acc_ibm}],
    }
    if anim["tracks"]:
        times = anim["times"]
        acc_time = binb.add(gs.pack_floats(times), len(times), "SCALAR", gs.FLOAT, ([times[0]], [times[-1]]))
        samplers, channels = [], []
        for bone, path, values in anim["tracks"]:
            if path == "translation":
                data, kind = [tuple(c * SCALE for c in v) for v in values], "VEC3"
            elif path == "rotation":
                data, kind = values, "VEC4"
            else:
                data, kind = values, "VEC3"
            acc_out = binb.add(gs.pack_floats(data), len(data), kind, gs.FLOAT)
            samplers.append({"input": acc_time, "output": acc_out, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": bone, "path": path}})
        gltf["animations"] = [{"name": ANIM_NAME, "channels": channels, "samplers": samplers}]
    gltf.update({
        "accessors": binb.accessors,
        "bufferViews": binb.views,
        "buffers": [{"byteLength": len(binb.data)}],
    })
    json_bytes = json.dumps(gltf, separators=(",", ":"), sort_keys=True).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = bytes(binb.data) + b"\x00" * ((4 - len(binb.data) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    out += struct.pack("<II", len(bin_bytes), 0x004E4942) + bin_bytes
    return out


# ---------------------------------------------------------------- animation (T-25b)

ANIM_NAME = "minemon_cobblemon"
# The six standard clips: name, first and last frame, the same as tools/gen_standins.py (one clip per .glb).
CLIP_RANGES = (("stand", 0, 20), ("walk", 21, 41), ("run", 42, 52), ("punch", 53, 63), ("die", 64, 74),
               ("sit", 75, 85))
LAST_FRAME = 85
BEDROCK_PATHS = ("rotation", "position", "scale")
# Clip names that are posing variants, tests or placeholders, not a plain idle or walk.
JUNK_WORDS = ("test", "wip", "old", "placeholder", "quirk", "overlay", "unbaked", "speed", "basket", "pose", "base")


def molang_context():
    """The molang package's evaluation context, with Bedrock's degree trigonometry (the package uses radians)."""
    try:
        import molang
    except ImportError as e:
        raise SystemExit("FAIL: the molang package is missing (pip install molang); the T-25b bake needs it") from e
    ctx = molang.create_context()
    m = ctx["math"]
    m["sin"] = lambda d: math.sin(math.radians(d))
    m["cos"] = lambda d: math.cos(math.radians(d))
    m["tan"] = lambda d: math.tan(math.radians(d))
    m["asin"] = lambda v: math.degrees(math.asin(max(-1.0, min(1.0, v))))
    m["acos"] = lambda v: math.degrees(math.acos(max(-1.0, min(1.0, v))))
    m["atan"] = lambda v: math.degrees(math.atan(v))
    m["atan2"] = lambda y, x: math.degrees(math.atan2(y, x))
    return molang, ctx


MATH_FUNCTION = re.compile(r"math\.([A-Za-z_]\w*)")


class Molang:
    """Evaluates a Bedrock Molang expression at a clip time (q.anim_time). Unknown queries and functions read as 0.

    Molang is case-insensitive, so math.Sin is math.sin. The count of expressions that read as 0 for an unknown
    function or a syntax the package lacks is kept in self.unknown, for the report."""

    def __init__(self):
        self.package, self.ctx = molang_context()
        self.normal = {}
        self.unknown = collections.Counter()

    def __call__(self, text, t):
        expr = self.normal.get(text)
        if expr is None:
            expr = self.normal[text] = MATH_FUNCTION.sub(lambda m: "math." + m.group(1).lower(), text)
        self.ctx["query"]["anim_time"] = t
        try:
            return float(self.package.eval(expr, self.ctx))
        except (NameError, SyntaxError, ValueError, TypeError, ZeroDivisionError, OverflowError):
            self.unknown[expr] += 1
            return 0.0


def _lerp(a, b, u):
    return tuple(x + (y - x) * u for x, y in zip(a, b))


def _catmull(p0, p1, p2, p3, u):
    out = []
    for a, b, c, d in zip(p0, p1, p2, p3):
        out.append(0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u
                          + (-a + 3 * b - 3 * c + d) * u * u * u))
    return tuple(out)


def _keyframes(chan):
    """[(time, pre, post, lerp_mode)] sorted by time, from one Bedrock channel; [] when there is none.

    A channel is a list (constant), or a dict of time -> list or {pre, post, vector, lerp_mode}. A key whose time is
    Molang is skipped."""
    if chan is None:
        return []
    if isinstance(chan, list):
        return [(0.0, chan, chan, "linear")]
    if not isinstance(chan, dict):
        return []
    keys = []
    for key, value in chan.items():
        try:
            when = float(key)
        except ValueError:
            continue
        if isinstance(value, list):
            pre = post = value
            lerp = "linear"
        elif isinstance(value, dict):
            vec = value.get("vector")
            pre = value.get("pre", vec)
            post = value.get("post", vec)
            if pre is None:
                pre = post
            if post is None:
                post = pre
            if pre is None:
                continue
            lerp = value.get("lerp_mode", "linear")
        else:
            continue
        keys.append((when, pre, post, lerp))
    keys.sort(key=lambda k: k[0])
    return keys


class BedrockClip:
    """One Bedrock animation, sampled at u in [0, 1] across its frame range: u maps to clip time u * length, so a
    loop fills its range and a one-shot plays once across it. Bones are deltas on the rest pose."""

    def __init__(self, anim, molang):
        self.molang = molang
        self.bones = {}
        longest = 0.0
        for bone, channels in (anim.get("bones") or {}).items():
            chans = {}
            for path in BEDROCK_PATHS:
                keys = _keyframes(channels.get(path))
                if keys:
                    chans[path] = keys
                    longest = max(longest, keys[-1][0])
            if chans:
                self.bones[bone] = chans
        length = anim.get("animation_length")
        self.length = float(length) if length else (longest or 1.0)

    def _vec(self, raw, t):
        out = [self.molang(c, t) if isinstance(c, str) else float(c) for c in list(raw)[:3]]
        while len(out) < 3:
            out.append(0.0)
        return tuple(out)

    def _at(self, keys, t):
        times = [k[0] for k in keys]
        if t < times[0]:
            return self._vec(keys[0][1], t)
        if t >= times[-1]:
            return self._vec(keys[-1][2], t)
        i = bisect.bisect_right(times, t) - 1
        if t == times[i]:
            return self._vec(keys[i][2], t)
        u = (t - times[i]) / (times[i + 1] - times[i])
        p1 = self._vec(keys[i][2], t)
        p2 = self._vec(keys[i + 1][1], t)
        if keys[i][3] == "catmullrom":
            p0 = self._vec(keys[i - 1][2], t) if i > 0 else p1
            p3 = self._vec(keys[i + 2][1], t) if i + 2 < len(keys) else p2
            return _catmull(p0, p1, p2, p3, u)
        return _lerp(p1, p2, u)

    def sample(self, u):
        t = min(max(u, 0.0), 1.0) * self.length
        return {bone: {path: self._at(keys, t) for path, keys in chans.items()} for bone, chans in self.bones.items()}


class Static:
    """No clip: the rest pose (the last fallback)."""

    def sample(self, u):
        return {}


class Repeat:
    """The walk played twice over the range: the run fallback (the walk, sped up)."""

    def __init__(self, clip, times):
        self.clip = clip
        self.times = times

    def sample(self, u):
        return self.clip.sample(1.0 if u >= 1.0 else (u * self.times) % 1.0)


def _ease(u):
    return 0.5 - 0.5 * math.cos(math.pi * min(max(u, 0.0), 1.0))


class Lunge:
    """The punch fallback: the root steps forward (Bedrock -z is the front) and back."""

    def __init__(self, root):
        self.root = root

    def sample(self, u):
        return {self.root: {"position": (0.0, 0.0, -4.0 * math.sin(math.pi * min(max(u, 0.0), 1.0)))}}


class Roll:
    """The die fallback: the root rolls a quarter turn onto its side and lifts a little, so it stays above ground."""

    def __init__(self, root):
        self.root = root

    def sample(self, u):
        s = _ease(u)
        return {self.root: {"rotation": (0.0, 0.0, 90.0 * s), "position": (0.0, 3.0 * s, 0.0)}}


class Squat:
    """The sit fallback: the root lowers and tips forward."""

    def __init__(self, root):
        self.root = root

    def sample(self, u):
        s = _ease(u)
        return {self.root: {"rotation": (-12.0 * s, 0.0, 0.0), "position": (0.0, -3.0 * s, 0.0)}}


def load_clips(anim_dir):
    """The Bedrock clips of one species' animation folder, by short name (the first file that has one wins)."""
    clips = {}
    if not os.path.isdir(anim_dir):
        return clips
    for entry in sorted(os.listdir(anim_dir)):
        if not entry.endswith(".animation.json"):
            continue
        with open(os.path.join(anim_dir, entry), encoding="utf-8") as f:
            data = json.load(f)
        for key, anim in (data.get("animations") or {}).items():
            clips.setdefault(key.rsplit(".", 1)[-1], anim)
    return clips


def _first_of(clips, names):
    return next((n for n in names if n in clips), None)


def _search(clips, word):
    for name in sorted(clips):
        if word in name and not any(junk in name for junk in JUNK_WORDS):
            return name
    return None


def choose_clips(clips, body_plan):
    """The Bedrock clip name for each frame range, or None where the fallback is used. Avian species fly for stand
    and walk (air_idle, air_fly); fish swim (water_swim)."""
    if body_plan == "avian":
        stand_first, walk_first = ["air_idle"], ["air_fly"]
    elif body_plan == "fish":
        stand_first, walk_first = ["water_swim"], ["water_swim"]
    else:
        stand_first, walk_first = [], []
    return {
        "stand": _first_of(clips, stand_first + ["ground_idle", "battle_idle"]) or _search(clips, "idle"),
        "walk": _first_of(clips, walk_first + ["ground_walk"]) or _search(clips, "walk"),
        "run": _first_of(clips, ["ground_run"]),
        "punch": _first_of(clips, ["physical", "attack"]),
        "die": _first_of(clips, ["faint"]),
        "sit": _first_of(clips, ["sleep"]),
    }


def build_plan(clips, names, molang, root):
    """The clip object for each frame range, and where each came from (a Bedrock clip name or 'fallback')."""
    def bedrock(key):
        return BedrockClip(clips[names[key]], molang) if names[key] else None

    plan = {"stand": bedrock("stand") or Static()}
    plan["walk"] = bedrock("walk") or plan["stand"]
    plan["run"] = bedrock("run") or Repeat(plan["walk"], 2)
    plan["punch"] = bedrock("punch") or Lunge(root)
    plan["die"] = bedrock("die") or Roll(root)
    plan["sit"] = bedrock("sit") or Squat(root)
    sources = {key: (names[key] or "fallback") for key, _first, _last in CLIP_RANGES}
    return plan, sources


def sample_frames(plan):
    """One pose per frame 0..LAST_FRAME: each range's clip at the fraction of its range that the frame is at."""
    poses = []
    for key, first, last in CLIP_RANGES:
        for frame in range(first, last + 1):
            poses.append(plan[key].sample((frame - first) / float(last - first)))
    return poses


def _varies(values):
    first = values[0]
    return any(abs(a - b) > 1e-6 for v in values for a, b in zip(v, first))


def _continuous(path, values):
    """Quaternions with no sign flips between frames, so that a slerp never turns the long way round."""
    out = []
    for v in values:
        v = tuple(v)
        if path == "rotation" and out and sum(a * b for a, b in zip(v, out[-1])) < 0:
            v = tuple(-c for c in v)
        out.append(v)
    return out


def bake_clip(geometry, clips, body_plan, molang):
    """The posed model of one species and its clip (T-25b). Returns (model, anim, sources).

    The model is grounded in the stand clip's frame 0. anim["rest"] holds that frame's node transforms, and
    anim["tracks"] (bone, path, values) the channels for every bone that moves over the clip."""
    rest = build_model(geometry)
    names = choose_clips(clips, body_plan)
    plan, sources = build_plan(clips, names, molang, rest["names"][rest["roots"][0]])
    poses = sample_frames(plan)
    model = build_model(geometry, poses[0])
    frames = [pose_nodes(model, pose) for pose in poses]
    tracks = []
    for i in range(len(model["names"])):
        series = (
            ("translation", [frame[0][i][1] for frame in frames]),
            ("rotation", [frame[0][i][0] for frame in frames]),
            ("scale", [frame[1][i] for frame in frames]),
        )
        for path, values in series:
            values = _continuous(path, values)
            if _varies(values):
                tracks.append((i, path, values))
    anim = {
        "times": [float(f) for f in range(LAST_FRAME + 1)],
        "tracks": tracks,
        "rest": (frames[0][0], frames[0][1]),
    }
    return model, anim, sources


# ---------------------------------------------------------------- the Cobblemon source tree

def discover(src):
    """Maps national dex number to (folder name, species name) for the entity model folders."""
    base = os.path.join(src, SOURCE_SUBDIR)
    entity_dir = os.path.join(base, "models", "entity")
    if not os.path.isdir(entity_dir):
        raise SystemExit("FAIL: %s not found (run scripts/setup.sh)" % entity_dir)
    found = {}
    for entry in sorted(os.listdir(entity_dir)):
        match = re.match(r"^(\d{4})_(.+)$", entry)
        if match and os.path.isdir(os.path.join(entity_dir, entry)):
            dex = int(match.group(1))
            found.setdefault(dex, (entry, match.group(2)))
    return base, found


def choose_geometry(path):
    """The model's main geometry: the first one that is not the held-item companion (.held)."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for geometry in data.get("minecraft:geometry", []):
        if not geometry["description"]["identifier"].endswith(".held"):
            return geometry
    raise ValueError("no main geometry in %s" % os.path.basename(path))


def _form_key(stem):
    """'mr_mime' and 'mrmime' give the same key, and a male or female suffix is dropped."""
    stem = stem.lower()
    for suffix in ("_male", "_female"):
        if stem.endswith(suffix):
            stem = stem[:-len(suffix)]
    return stem.replace("_", "")


def find_geo_stem(models_dir, name):
    """The stem of the species' base model. Order: <name>, <name>_male, the same name without underscores
    (the folder 0122_mrmime holds mr_mime.geo.json), then the first form named <name>_... (Unown's a form)."""
    stems = sorted(f[:-len(".geo.json")] for f in os.listdir(models_dir) if f.endswith(".geo.json"))
    for stem in (name, name + "_male"):
        if stem in stems:
            return stem
    for stem in stems:
        if _form_key(stem) == name.replace("_", ""):
            return stem
    for stem in stems:
        if stem.startswith(name + "_"):
            return stem
    return None


def convert_species(base, dex, folder_name, name, body_plan, molang):
    """Returns (model, anim, base texture path, shiny texture path or None, clip sources), or raises ValueError."""
    models_dir = os.path.join(base, "models", "entity", folder_name)
    tex_dir = os.path.join(base, "textures", "entity", folder_name)
    geo_stem = find_geo_stem(models_dir, name)
    if geo_stem is None:
        raise ValueError("no base geo model in %s" % folder_name)
    geometry = choose_geometry(os.path.join(models_dir, geo_stem + ".geo.json"))
    tex_stem = None
    for stem in (geo_stem, name, name + "_male"):
        if os.path.isfile(os.path.join(tex_dir, stem + ".png")):
            tex_stem = stem
            break
    if tex_stem is None:
        raise ValueError("no texture for %s in %s" % (geo_stem, folder_name))
    base_png = os.path.join(tex_dir, tex_stem + ".png")
    shiny_png = os.path.join(tex_dir, tex_stem + "_shiny.png")
    if not os.path.isfile(shiny_png):
        shiny_png = None
    clips = load_clips(os.path.join(base, "animations", folder_name))
    random.seed(dex)  # Molang's math.random reads Python's generator: the bake is the same on every run
    model, anim, sources = bake_clip(geometry, clips, body_plan, molang)
    return model, anim, base_png, shiny_png, sources


def load_body_plans(path):
    """dex -> body_plan, from the species data (mods/minemon/minemon_core/data/species.json). {} when absent."""
    if not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return {int(s["id"]): s.get("body_plan") for s in json.load(f)}


def lua_number(value):
    return "%.3f" % value


def anims_lua():
    return "{%s}" % ", ".join("%s = {%d, %d}" % (key, first, last) for key, first, last in CLIP_RANGES)


def write_pack(out_dir, converted, commit):
    pack = os.path.join(out_dir, PACK_NAME)
    if os.path.isdir(pack):
        shutil.rmtree(pack)
    os.makedirs(os.path.join(pack, "models"))
    os.makedirs(os.path.join(pack, "textures"))
    with open(os.path.join(pack, "mod.conf"), "w", encoding="utf-8") as f:
        f.write("name = %s\n" % PACK_NAME)
        f.write("description = Cobblemon creature models converted by tools/cobblemon_import.py "
                "(generated; not committed; see CREDITS.txt).\n")
    lines = [
        "-- Generated by tools/cobblemon_import.py (T-25a, T-25b). Do not edit: run scripts/setup.sh to regenerate.",
        "-- Assets from kirbycope/cobblemon-bedrock (commit %s). Credits and licence: CREDITS.txt." % commit,
        "-- Each model is one glTF with one clip: stand, walk, run, punch, die and sit at the frame ranges in anims",
        "-- (the same for every species). height and width are the rest model's bounding box in nodes; scale_hint",
        "-- is the larger of the two, the size a consumer scales by.",
        "minemon_pack = rawget(_G, \"minemon_pack\") or {}",
        "minemon_pack.models = {",
    ]
    anims = anims_lua()
    for dex, _name, model, _shiny in converted:
        lines.append("\t[%d] = {mesh = \"mmp_%04d.glb\", texture = \"mmp_%04d.png\","
                     " texture_shiny = \"mmp_%04d_s.png\"," % (dex, dex, dex, dex))
        lines.append("\t\theight = %s, width = %s, scale_hint = %s,"
                     % (lua_number(model["height"]), lua_number(model["width"]), lua_number(model["scale_hint"])))
        lines.append("\t\tanims = %s}," % anims)
    lines.append("}")
    with open(os.path.join(pack, "init.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    credits = [
        "Minemon pack: Cobblemon creature models (generated at build time; never committed to the repository).",
        "",
        "Source: https://github.com/kirbycope/cobblemon-bedrock at commit %s." % commit,
        "The code of that repository is MIT. Each model folder carries its own licence file (Creative Commons,",
        "non-commercial, attribution). Cobblemon, the upstream project, is MPL-2.0 for its code; its asset licence",
        "is not stated at the root of its repository.",
        "",
        "Modified: format conversion to Luanti glTF (.glb, one skinned mesh per species with one clip of the standard",
        "frame ranges, baked from Bedrock animations with the molang package) and copies of the Bedrock PNG textures,",
        "by tools/cobblemon_import.py. The shiny texture is the base texture where the source ships no shiny one.",
        "",
        "Private, non-commercial use only. Never publish a build that contains this pack (D-029).",
        "",
    ]
    with open(os.path.join(pack, "CREDITS.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(credits))
    for dex, _name, model, shiny in converted:
        with open(os.path.join(pack, "models", "mmp_%04d.glb" % dex), "wb") as f:
            f.write(write_glb(model, model["anim"]))
        shutil.copyfile(model["base_png"], os.path.join(pack, "textures", "mmp_%04d.png" % dex))
        shiny_src = shiny if shiny else model["base_png"]
        shutil.copyfile(shiny_src, os.path.join(pack, "textures", "mmp_%04d_s.png" % dex))
    return pack


def main(argv=None):
    parser = argparse.ArgumentParser(description="Convert Cobblemon Bedrock models to a Luanti pack (T-25a, T-25b).")
    parser.add_argument("--src", required=True, help="the cobblemon-bedrock clone")
    parser.add_argument("--out", required=True, help="output directory; the pack mod is written inside it")
    parser.add_argument("--only", default="", help="comma-separated dex numbers to convert (default: all 1-251)")
    parser.add_argument("--commit", default="unknown", help="the pinned source commit, written into the pack")
    parser.add_argument("--species", default=DEFAULT_SPECIES, help="species data with body_plan per dex")
    args = parser.parse_args(argv)

    base, found = discover(args.src)
    if args.only:
        wanted = [int(x) for x in args.only.split(",") if x.strip()]
    else:
        wanted = list(range(1, DEX_MAX + 1))
    plans = load_body_plans(args.species)
    if not plans:
        print("cobblemon_import: no species data at %s: avian and fish clips are not chosen" % args.species)
    evaluator = Molang()
    converted, failed = [], []
    shiny_fallbacks = 0
    source_counts = {key: collections.Counter() for key, _first, _last in CLIP_RANGES}
    for dex in wanted:
        if dex not in found:
            failed.append((dex, "no entity folder"))
            continue
        folder_name, name = found[dex]
        try:
            model, anim, base_png, shiny_png, sources = convert_species(
                base, dex, folder_name, name, plans.get(dex), evaluator)
        except (ValueError, KeyError, IndexError, OSError, TypeError, ZeroDivisionError) as e:
            failed.append((dex, str(e)))
            continue
        (lo, hi) = model["bounds_px"]
        model["height"] = (hi[1] - lo[1]) / PX_PER_BLOCK
        model["width"] = max(hi[0] - lo[0], hi[2] - lo[2]) / PX_PER_BLOCK
        model["scale_hint"] = max(model["height"], model["width"])
        model["base_png"] = base_png
        model["anim"] = anim
        for key, source in sources.items():
            source_counts[key][source] += 1
        if shiny_png is None:
            shiny_fallbacks += 1
        converted.append((dex, name, model, shiny_png))
    os.makedirs(args.out, exist_ok=True)
    pack = write_pack(args.out, converted, args.commit)
    print("cobblemon_import: converted %d of %d species into %s" % (len(converted), len(wanted), pack))
    print("cobblemon_import: shiny textures falling back to base: %d" % shiny_fallbacks)
    for key, _first, _last in CLIP_RANGES:
        top = ", ".join("%s %d" % kv for kv in source_counts[key].most_common(6))
        print("cobblemon_import: clip %s from: %s" % (key, top or "nothing"))
    print("cobblemon_import: Molang expressions that read as 0 (unknown function or syntax): %d kinds, %d uses"
          % (len(evaluator.unknown), sum(evaluator.unknown.values())))
    for dex, reason in failed:
        print("cobblemon_import: FAIL dex %d: %s" % (dex, reason))
    if not args.only and len(converted) < FULL_RUN_MIN:
        print("cobblemon_import: FAIL only %d species converted (need %d)" % (len(converted), FULL_RUN_MIN))
        return 1
    if args.only and failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
