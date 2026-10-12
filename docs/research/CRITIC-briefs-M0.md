# CRITIC: M0 briefs (T-01 to T-05)

Read: CLAUDE.md, CONVENTIONS, PLAN, T-01..T-05. No project.godot, scripts/, core/ or data/ exist yet (expected). Checked: GUT docs give exit 0 (all pass) and 1 (any fail), with no code for zero tests. Unverified: gdtoolkit config filename.

## BLOCKER
1. T-02/T-03/T-04 run in parallel, but each needs `check.sh` exit 0, and check.sh lints, formats and tests the whole repo. One half-written file blocks all. Fix: workers check only their own files; Opus runs check.sh after merge.
2. T-01 line 47: "All 17 InputMap actions", but line 18 lists 18. Fix: "18".
3. T-01 line 31 (4d): no GUT command given, and GUT defines no non-zero exit for zero tests. Fix: give the exact command plus a count check (e.g. `-gjunit_xml_file`, require >0 testcases).

## MAJOR
4. T-03 line 35: the `world/world_rng.gd` fallback is a second RNG (breaks invariant 2) and hides a T-02 dependency. Fix: T-03 depends on T-02; delete the fallback.
5. T-02 line 37 and T-04 line 37 both edit project.godot autoloads with no order. T-05 rewires main.tscn, which T-01 line 34 tests. Fix: T-01 registers all M0 autoloads as stubs; main keeps a direct Camera3D.
6. T-02 lines 11, 26: CombatantView/DamageResult fields, SpeciesData/MoveData constructors, the types.json schema, and core/typechart.gd (in PLAN tree, no owner) are undefined. Fix: specify them.
7. T-02 lines 14, 43: "not-yet-loaded id" has no rule; "each broken field" has no fixture. Fix: evolution targets must be 1–251; list fixture fields and expected errors.
8. T-03 line 41 vs CONVENTIONS line 14: a timed test breaks "no wall-clock time" and runs inside check.sh. Fix: move the benchmark out of tests/.
9. T-03 line 31: radius-1 chunk count undefined (72 under a square metric); no rule for waiting on WorkerThreadPool. Fix: state both.
10. T-05 lines 14, 17, 19: spawn height, collision readiness and "20 m above terrain" need queries T-03 lacks (line 20 exposes only loaded_chunk_count). Fix: add `surface_height(x,z)` and `is_ready_at(pos)` to T-03.

## MINOR
11. T-02 lines 20, 22: exp growth curves absent; catch takes hp_frac but the formula uses max/cur. Fix: list curves; state the conversion.
12. T-03 lines 21, 28: "world/rng from core/rng.gd" is contradictory; neighbour dict format and face-count method undefined.
13. T-05 lines 22, 39-40: `--bench-seconds` placement unstated; zip/unzip may be missing; .tpz extraction step missing.
14. T-01 lines 25-26; T-02 line 37: GUT version unpinned; `gdlintrc` may need a leading dot (unverified); tests/fixtures is outside the PLAN tree that T-01 line 11 says to match exactly.
15. T-01 line 16: a Label under Node3D won't show as a HUD. Fix: wrap it in a CanvasLayer.
