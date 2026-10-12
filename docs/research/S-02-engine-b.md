# S-02 Engine foundation (engine-b)

## Findings
- Godot 4.7 stable released 2026-06-19; 4.7.2 maintenance followed (Aug 2026).
- Official Godot docs say Godot 4 C# projects cannot export to Android (PR #7551). I found no 4.7 change to that.
- Mobile and Forward+ need Vulkan. Mesa lists Ivy Bridge (HD 4000) Vulkan as incomplete, so Compatibility (OpenGL) is the realistic PC renderer. Intel OpenGL driver regressions have hit Godot before (#23069, fixed in driver 25.20.100.x).
- GUT 9.7.1 (4.7 branch) runs headless with `-s addons/gut/gut_cmdln.gd -gexit` (exit 0 pass, 1 fail). gdUnit4 v6.2.2 has a CLI and C# support. gdtoolkit 4.5.0 (Oct 2025) gives gdlint and gdformat.
- Luanti has official Android builds. Its docs give no minimum Android version, benchmarks or test framework.
- Cobblemon is MPL-2.0 and Java-only. No Android path.
- Zylann godot_voxel is a C++ module with unfinished GDExtension support.
- No sourced voxel benchmark for Intel HD found.

## Recommendation
Godot 4.7.x with GDScript and the Compatibility renderer on both PC and Android. Write a custom 16^3 chunk mesher on WorkerThreadPool, and move to GDExtension only if profiling demands it. Test with GUT and lint with gdtoolkit. Start at a 4-6 chunk view radius and measure on the target PC. Reject C# (no Android export) and Cobblemon (Java-only, heavy). Keep Luanti as fallback.

## Confidence
Medium. Engine, tooling and licence facts come from primary sources. Intel HD voxel performance is unmeasured. The Android Compatibility details and GDExtension-on-Android status are unverified.

| Option | Android | Intel HD fit | Headless tests | Verdict |
|---|---|---|---|---|
| Godot 4.7 GDScript, Compatibility | Yes | OpenGL path; no Vulkan needed | GUT 9.7.1 | Recommended |
| Godot 4 C# | No (docs) | Same renderer | gdUnit4 | Reject for Android |
| Godot voxel module (Zylann) | Unverified | n/a | n/a | Avoid for now |
| Luanti 5.x | Yes (official) | Low reqs, unmeasured | Lua, no standard framework found | Fallback |
| Minecraft Java + Cobblemon | No | Heavy on 6 GB | none standard | Reject |
| Unity 6 (C#) | Yes (ES 3.1+ or Vulkan, Android 8+) | DX10/11/12 or Vulkan editor | Unity Test Framework | Heavier alternative |

## Sources
- https://app.cinevva.com/hi/news/2026-06-19-godot-4-7-released
- https://gamedev.net/news/5172-godot-engine-472-stable-released/
- https://godotengine.org/releases/4.6/
- https://github.com/godotengine/godot-docs/pull/7551/files
- https://github.com/godotengine/godot/issues/23069
- https://gitlab.freedesktop.org/mesa/mesa/-/issues/8249
- https://github.com/bitwes/Gut
- https://gut.readthedocs.io/en/latest/Command-Line.html
- https://github.com/MikeSchulze/gdUnit4
- https://pypi.org/project/gdtoolkit/
- https://docs.luanti.org/for-creators/mobile/
- https://modrinth.com/mod/cobblemon
- https://github.com/Zylann/godot_voxel
- https://docs.unity3d.com/Manual/system-requirements

## Open questions
- Which GPU is the test PC: HD 4000 (no Vulkan) or HD 4600+? This decides whether Mobile renderer is viable.
- Realistic chunk radius on the target PC: needs a prototype benchmark.
- Does GUT run under `--headless` on Linux workers? Not verified.
- Current Godot 4.7 docs on C# and Android: the fetch failed, so this relies on the 2024-era PR.
- Luanti minimum Android version and combat-entity limits.
