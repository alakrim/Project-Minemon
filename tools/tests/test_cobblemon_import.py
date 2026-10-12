"""Unit tests for tools/cobblemon_import.py (T-25a). Run: python3 -m unittest discover -s tools/tests"""

import math
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import cobblemon_import as ci  # noqa: E402


def _close(a, b, tol=1e-6):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def _matrix_from_column_major(m):
    """Row-major 3x4 view of a glTF column-major mat4 (the bottom row is 0 0 0 1)."""
    return [[m[0], m[4], m[8], m[12]],
            [m[1], m[5], m[9], m[13]],
            [m[2], m[6], m[10], m[14]]]


def _apply_column_major(m, p):
    rows = _matrix_from_column_major(m)
    return tuple(rows[r][0] * p[0] + rows[r][1] * p[1] + rows[r][2] * p[2] + rows[r][3] for r in range(3))


# A two-bone geometry: a root cube and a child cube rotated about z, so the inverse bind is not a pure translation.
SYNTHETIC = {
    "description": {"identifier": "geometry.test", "texture_width": 32, "texture_height": 16},
    "bones": [
        {"name": "root", "pivot": [0, 24, 0],
         "cubes": [{"origin": [-2, 24, -2], "size": [4, 8, 4], "uv": [0, 0]}]},
        {"name": "head", "parent": "root", "pivot": [0, 30, 0], "rotation": [0, 0, 30],
         "cubes": [{"origin": [-3, 30, -1], "size": [6, 5, 3], "uv": [16, 0], "inflate": 0.5,
                    "mirror": True}]},
    ],
}


class BoxUvTests(unittest.TestCase):
    def test_box_layout_matches_minecraft_unwrap(self):
        rects = ci.box_uv_rects(0, 0, 4, 8, 4)
        self.assertEqual(rects["east"], (0, 4, 4, 12))
        self.assertEqual(rects["north"], (4, 4, 8, 12))
        self.assertEqual(rects["west"], (8, 4, 12, 12))
        self.assertEqual(rects["south"], (12, 4, 16, 12))
        self.assertEqual(rects["up"], (4, 0, 8, 4))
        self.assertEqual(rects["down"], (8, 0, 12, 4))

    def test_mirror_swaps_u(self):
        rect = (0, 0, 4, 4)
        plain = ci.face_uv_corners(rect, False)
        mirrored = ci.face_uv_corners(rect, True)
        self.assertEqual(plain, [(0, 4), (4, 4), (4, 0), (0, 0)])
        self.assertEqual(mirrored, [(4, 4), (0, 4), (0, 0), (4, 0)])

    def test_per_face_uv_with_negative_size_keeps_order(self):
        cube = {"origin": [0, 0, 0], "size": [4, 4, 4],
                "uv": {"north": {"uv": [4, 4], "uv_size": [-4, 4]}, "up": {"uv": [0, 0], "uv_size": [4, 4]}}}
        faces = {face: rect for face, rect, _m in ci.cube_faces(cube, False)}
        self.assertEqual(faces["north"], (4.0, 4.0, 0.0, 8.0))
        self.assertEqual(faces["up"], (0.0, 0.0, 4.0, 4.0))
        self.assertEqual(set(faces), {"north", "up"})

    def test_bone_mirror_applies_when_cube_does_not_say(self):
        cube = {"origin": [0, 0, 0], "size": [4, 4, 4], "uv": [0, 0]}
        self.assertTrue(all(m for _f, _r, m in ci.cube_faces(cube, True)))
        self.assertFalse(any(m for _f, _r, m in ci.cube_faces(cube, False)))


class BoundsTests(unittest.TestCase):
    def test_inflate_grows_each_side(self):
        lo, hi = ci.cube_bounds({"origin": [0, 0, 0], "size": [4, 8, 4], "inflate": 1})
        self.assertEqual(lo, (-1.0, -1.0, -1.0))
        self.assertEqual(hi, (5.0, 9.0, 5.0))

    def test_negative_size_gives_ordered_bounds(self):
        lo, hi = ci.cube_bounds({"origin": [2, 2, 2], "size": [-4, 4, 4]})
        self.assertEqual(lo, (-2.0, 2.0, 2.0))
        self.assertEqual(hi, (2.0, 6.0, 6.0))


class RotationTests(unittest.TestCase):
    def test_pivot_rotation_about_offset_point(self):
        rot = ci.pivot_rot(ci.q_axis((0, 0, 1), 90), (10.0, 0.0, 0.0))
        out = ci.t_apply(rot, (11.0, 0.0, 0.0))
        self.assertTrue(_close(out, (10.0, 1.0, 0.0), 1e-9))

    def test_euler_order_is_rz_ry_rx(self):
        # Rx(90) takes +y to +z; then Ry(90) takes +z to +x. Applying Ry first would give a different answer.
        out = ci.q_rot(ci.q_euler((90.0, 90.0, 0.0)), (0.0, 1.0, 0.0))
        self.assertTrue(_close(out, (1.0, 0.0, 0.0), 1e-9))

    def test_inverse_transform_undoes_transform(self):
        xf = ci.t_mul(ci.pivot_rot(ci.q_euler((10.0, 20.0, 30.0)), (1.0, 2.0, 3.0)),
                      ((0.0, 0.0, 0.0, 1.0), (5.0, -2.0, 7.0)))
        back = ci.t_mul(ci.t_inv(xf), xf)
        self.assertTrue(_close(back[0], ci.IDENTITY_Q, 1e-9))
        self.assertTrue(_close(back[1], (0.0, 0.0, 0.0), 1e-9))


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.model = ci.build_model(SYNTHETIC)

    def test_lowest_point_sits_at_zero(self):
        lowest = min(p[1] for p in self.model["positions"])
        self.assertAlmostEqual(lowest, 0.0, places=6)

    def test_inverse_bind_is_rigid_and_matches_the_cube_corners(self):
        # Joint-local coordinates are the inverse bind applied to each vertex. Each joint's frame is rigid, so the
        # distances between a joint's vertices in joint space must equal the distances between the same Bedrock
        # cube corners. The expected corners come from the same face order the converter uses.
        expected = []
        for bone_index, bone in enumerate(SYNTHETIC["bones"]):
            for cube in bone.get("cubes", []):
                lo, hi = ci.cube_bounds(cube)
                for face, _rect, _mirror in ci.cube_faces(cube, bool(bone.get("mirror", False))):
                    corners, _normal = ci.face_corners(lo, hi, face)
                    for corner in corners:
                        expected.append((bone_index, corner))
        self.assertEqual(len(expected), len(self.model["positions"]))
        local = []
        for p, j in zip(self.model["positions"], self.model["joints"]):
            glb = tuple(c * ci.SCALE for c in p)
            local.append((j[0], _apply_column_major(self.model["inverse_bind"][j[0]], glb)))
        for joint in (0, 1):
            pts = [(loc, exp[1]) for loc, exp in zip(local, expected) if exp[0] == joint and loc[0] == joint]
            self.assertTrue(pts)
            for a in range(len(pts)):
                for b in range(a + 1, len(pts)):
                    d_joint = math.dist(pts[a][0][1], pts[b][0][1])
                    d_bedrock = math.dist(pts[a][1], pts[b][1])
                    self.assertAlmostEqual(d_joint / ci.SCALE, d_bedrock, places=3)

    def test_every_vertex_is_fully_weighted_to_one_bone(self):
        for w, j in zip(self.model["weights"], self.model["joints"]):
            self.assertEqual(w[0], 1.0)
            self.assertEqual(j[1:], (0, 0, 0))

    def test_indices_form_quads(self):
        self.assertEqual(len(self.model["indices"]) % 6, 0)
        self.assertEqual(len(self.model["positions"]) % 4, 0)

    def test_inflate_grows_the_model(self):
        plain = json_copy(SYNTHETIC)
        plain["bones"][1]["cubes"][0].pop("inflate")
        base = ci.build_model(plain)
        width = lambda m: max(p[0] for p in m["positions"]) - min(p[0] for p in m["positions"])  # noqa: E731
        self.assertGreater(width(self.model), width(base))


class MolangTests(unittest.TestCase):
    """Molang as Bedrock reads it (T-25b): degrees, case-insensitive functions, q.anim_time, unknown queries 0."""

    def setUp(self):
        self.expr = ci.Molang()

    def test_trigonometry_is_in_degrees(self):
        self.assertAlmostEqual(self.expr("math.sin(90)", 0.0), 1.0, places=9)
        self.assertAlmostEqual(self.expr("math.cos(60)", 0.0), 0.5, places=9)
        self.assertAlmostEqual(self.expr("math.atan2(1, 1)", 0.0), 45.0, places=9)

    def test_anim_time_drives_the_expression(self):
        self.assertAlmostEqual(self.expr("math.sin(q.anim_time*90*4)*0.2", 0.25), 0.2, places=9)
        self.assertAlmostEqual(self.expr("query.anim_time * 2", 0.5), 1.0, places=9)

    def test_unknown_queries_read_as_zero(self):
        self.assertEqual(self.expr("q.look + q.walk_speed * 3", 1.0), 0.0)
        self.assertEqual(self.expr("q.life_time", 1.0), 0.0)

    def test_capitalised_functions_are_accepted(self):
        self.assertAlmostEqual(self.expr("math.Sin(90)", 0.0), 1.0, places=9)

    def test_clamp_and_ternary(self):
        self.assertEqual(self.expr("math.clamp(q.anim_time*10, -1, 1)", 0.5), 1.0)
        self.assertEqual(self.expr("q.anim_time > 0.2 ? 3 : 4", 0.1), 4.0)

    def test_failing_expression_reads_zero_and_is_counted(self):
        self.assertEqual(self.expr("math.no_such_function(1)", 0.0), 0.0)
        self.assertEqual(sum(self.expr.unknown.values()), 1)


class ClipSamplingTests(unittest.TestCase):
    """BedrockClip: keyframes, Molang channels and the mapping of a clip onto its frame range (T-25b)."""

    def setUp(self):
        self.expr = ci.Molang()

    def clip(self, bones, length=None, loop=True):
        anim = {"loop": loop, "bones": bones}
        if length is not None:
            anim["animation_length"] = length
        return ci.BedrockClip(anim, self.expr)

    def test_linear_keys_interpolate_over_the_clip_length(self):
        c = self.clip({"b": {"rotation": {"0.0": [0, 0, 0], "1.0": [0, 0, 10]}}}, length=2.0)
        self.assertTrue(_close(c.sample(0.25)["b"]["rotation"], (0, 0, 5)))  # clip time 0.5
        self.assertTrue(_close(c.sample(1.0)["b"]["rotation"], (0, 0, 10)))  # clip time 2.0 (the last key)

    def test_constant_channel_holds(self):
        c = self.clip({"b": {"position": [0, 1, 0]}}, length=1.0)
        for u in (0.0, 0.3, 1.0):
            self.assertTrue(_close(c.sample(u)["b"]["position"], (0, 1, 0)))

    def test_step_keys_use_post_leaving_and_pre_arriving(self):
        c = self.clip({"b": {"rotation": {"0.0": {"post": [0, 0, 0]}, "1.0": {"pre": [5, 0, 0]}}}}, length=1.0)
        self.assertTrue(_close(c.sample(0.5)["b"]["rotation"], (2.5, 0, 0)))

    def test_molang_channel_is_evaluated_at_the_clip_time(self):
        c = self.clip({"b": {"rotation": ["math.sin(q.anim_time*90)*10", 0, 0]}}, length=1.0)
        self.assertAlmostEqual(c.sample(0.25)["b"]["rotation"][0], 10 * math.sin(math.radians(22.5)), places=6)

    def test_catmullrom_matches_linear_on_a_straight_run(self):
        keys = {"0.0": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
                "1.0": {"post": [10, 0, 0], "lerp_mode": "catmullrom"},
                "2.0": [10, 0, 0]}
        c = self.clip({"b": {"position": keys}}, length=2.0)
        self.assertAlmostEqual(c.sample(0.25)["b"]["position"][0], 5.0, places=6)  # clip time 0.5

    def test_loop_length_defaults_to_the_last_key(self):
        c = self.clip({"b": {"rotation": {"0.0": [0, 0, 0], "3.0": [0, 0, 6]}}})
        self.assertEqual(c.length, 3.0)


class ChooseClipTests(unittest.TestCase):
    def test_standard_species_use_the_ground_clips(self):
        clips = {"ground_idle": {}, "ground_walk": {}, "faint": {}, "sleep": {}}
        names = ci.choose_clips(clips, "biped")
        self.assertEqual((names["stand"], names["walk"], names["die"], names["sit"]),
                         ("ground_idle", "ground_walk", "faint", "sleep"))
        self.assertIsNone(names["run"])
        self.assertIsNone(names["punch"])

    def test_avian_species_fly_for_stand_and_walk(self):
        names = ci.choose_clips({"air_idle": {}, "air_fly": {}, "ground_idle": {}}, "avian")
        self.assertEqual((names["stand"], names["walk"]), ("air_idle", "air_fly"))

    def test_fish_species_swim_for_stand_and_walk(self):
        names = ci.choose_clips({"water_swim": {}, "ground_idle": {}}, "fish")
        self.assertEqual((names["stand"], names["walk"]), ("water_swim", "water_swim"))

    def test_variants_and_tests_are_not_picked_as_idle(self):
        self.assertIsNone(ci.choose_clips({"idle_quirk": {}, "idle_pose": {}}, "biped")["stand"])
        self.assertEqual(ci.choose_clips({"idle2": {}}, "biped")["stand"], "idle2")

    def test_missing_clips_use_the_fallbacks(self):
        plan, sources = ci.build_plan({}, ci.choose_clips({}, "biped"), ci.Molang(), "root")
        self.assertIsInstance(plan["punch"], ci.Lunge)
        self.assertIsInstance(plan["run"], ci.Repeat)
        self.assertEqual(sources["die"], "fallback")


class PoseDeltaTests(unittest.TestCase):
    """Bedrock deltas on the rest pose: rotations add to the rest Euler angles, pivots move by position deltas."""

    def setUp(self):
        self.model = ci.build_model(SYNTHETIC)
        self.head = self.model["names"].index("head")
        self.root = self.model["names"].index("root")

    def test_no_pose_is_the_rest_pose(self):
        locals_, scales = ci.pose_nodes(self.model, {})
        for got, want in zip(locals_, self.model["local"]):
            self.assertTrue(_close(got[0], want[0]) and _close(got[1], want[1]))
        self.assertTrue(all(s == (1.0, 1.0, 1.0) for s in scales))

    def test_rotation_delta_adds_to_the_rest_euler_angles(self):
        locals_, _ = ci.pose_nodes(self.model, {"head": {"rotation": (0, 0, 10)}})
        self.assertTrue(_close(locals_[self.head][0], ci.q_euler((0, 0, 40))))

    def test_position_delta_moves_the_pivot_up(self):
        # Bedrock y runs up: a delta of +2 moves the head pivot from y = 30 to 28, so 4 px above the root pivot.
        locals_, _ = ci.pose_nodes(self.model, {"head": {"position": (0, 2, 0)}})
        self.assertTrue(_close(locals_[self.head][1], (0, 4, 0)))

    def test_root_position_delta_moves_the_model_up_in_glTF(self):
        rest = ci.pose_nodes(self.model, {})[0][self.root][1]
        moved = ci.pose_nodes(self.model, {"root": {"position": (0, 2, 0)}})[0][self.root][1]
        self.assertTrue(_close(sub3(moved, rest), (0, 2, 0)))

    def test_scale_delta_is_returned_per_bone(self):
        _, scales = ci.pose_nodes(self.model, {"head": {"scale": (0, 0, 0)}})
        self.assertEqual(scales[self.head], (0.0, 0.0, 0.0))
        self.assertEqual(scales[self.root], (1.0, 1.0, 1.0))

    def test_posed_model_is_grounded_in_that_pose(self):
        pose = {"head": {"position": (0, 6, 0), "rotation": (0, 0, 45)}}
        posed = ci.build_model(SYNTHETIC, pose)
        self.assertAlmostEqual(ci.posed_lowest_y(posed, pose), 0.0, places=6)


class BakeTests(unittest.TestCase):
    def setUp(self):
        self.expr = ci.Molang()
        clips = {"ground_idle": {"loop": True, "bones": {"head": {"rotation": {"0.0": [0, 0, 0], "1.0": [0, 0, 20]}}}}}
        self.model, self.anim, self.sources = ci.bake_clip(SYNTHETIC, clips, "biped", self.expr)
        self.head = self.model["names"].index("head")

    def track(self, bone, path):
        for b, p, values in self.anim["tracks"]:
            if b == bone and p == path:
                return values
        return None

    def test_stand_clip_and_fallbacks_are_reported(self):
        self.assertEqual(self.sources["stand"], "ground_idle")
        self.assertEqual(self.sources["punch"], "fallback")

    def test_the_clip_covers_frames_0_to_85(self):
        self.assertEqual(len(self.anim["times"]), 86)
        self.assertEqual((self.anim["times"][0], self.anim["times"][-1]), (0.0, 85.0))

    def test_rest_is_the_stand_frame_zero(self):
        rest_q = self.anim["rest"][0][self.head][0]
        self.assertTrue(_close(rest_q, ci.q_euler((0, 0, 30))))

    def test_stand_end_frame_has_the_full_delta(self):
        values = self.track(self.head, "rotation")
        self.assertIsNotNone(values)
        self.assertTrue(_close(values[20], ci.q_euler((0, 0, 50))))

    def test_a_bone_still_in_the_stand_range_has_no_motion_there(self):
        # The root moves in the punch, die and sit fallbacks, so it has a track; over frames 0-20 it stays at rest.
        values = self.track(self.model["names"].index("root"), "rotation")
        self.assertTrue(all(_close(v, (1.0, 0.0, 0.0, 0.0)) for v in values[:21]))

    def test_glb_carries_one_clip_with_86_keyframes(self):
        glb = ci.write_glb(self.model, self.anim)
        gltf = parse_glb(glb)
        self.assertEqual(len(gltf["animations"]), 1)
        self.assertEqual(gltf["accessors"][gltf["animations"][0]["samplers"][0]["input"]]["count"], 86)
        for channel in gltf["animations"][0]["channels"]:
            self.assertLess(channel["target"]["node"], len(gltf["nodes"]))


def sub3(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def parse_glb(data):
    import json
    import struct
    magic, version, total = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2 and total == len(data)
    length, kind = struct.unpack("<II", data[12:20])
    assert kind == 0x4E4F534A
    return json.loads(data[20:20 + length].decode("utf-8"))


def json_copy(data):
    import json
    return json.loads(json.dumps(data))


if __name__ == "__main__":
    unittest.main()
