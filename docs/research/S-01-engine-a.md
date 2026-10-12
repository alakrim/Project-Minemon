# S-01 — Engine choice for PokeCraft (scout digest)

| Option | Latest stable | Android path | Headless tests | Low-end / combat | Verdict |
|---|---|---|---|---|---|
| Godot 4.7 + GDScript, Compatibility renderer | 4.7 (18 Jun 2026), 4.7.2 (18 Aug 2026) | Yes | `--headless` mode | Renderer aimed at low-end; no HD 620 data | Recommended |
| Godot + godot_voxel GDExtension | Needs Godot 4.4.1+ | Android x86_64/arm64 listed | Same as Godot | Native mesher; "less tested" | Optional spike |
| Godot C# | 4.7.2 | Experimental (4.2 note); unverified for 4.7 | Needs .NET | n/a | Avoid for now |
| Luanti 5.17 (Lua mods) | 5.17.0 (Aug 2026) | Yes, official app | Server mode, no standard unit framework | Array textures; user-reported gains | Fallback |
| Minecraft Java + Cobblemon | n/a | No official build | Unclear | Heavy JVM | Reject |
| Unity 6 | 6.x | Yes | Batchmode; Linux editor Ubuntu-only | Heavier runtime | Avoid |
| Bevy 0.20 (Rust) | 0.20 (Oct 2026 per bevy.org) | `bevy_android` crate, status unstated | `cargo test`, no GPU needed | Fast; API churn each release | Watch |

## Findings
- Godot's Compatibility renderer is documented for "low-end desktop and mobile" but has no compute shaders. Godot 4.7 notes say Vulkan Mobile "matches or even outperforms" Compatibility in some benchmarks, so both must be measured.
- C# export to Android was "experimental" in the 4.2 article (Jan 2024); 4.x docs state C# projects cannot export to Android. Current status is unverified.
- godot_voxel is a "C++ module/extension". The module needs a custom engine build. The GDExtension is "newer and less tested".
- Only low-end evidence: one Feb 2026 forum post, about 30 fps at 1080p on an i5-8350 with UHD 620. No HD 620 benchmark found.
- Luanti 5.17 runs on Android. Desktop mods need adjustment for mobile.
- Minecraft Java runs officially only on Windows, macOS and Linux. Android needs third-party launchers.
- Unity Personal is free under $200k revenue/funding. The runtime fee was cancelled in 2024.

## Recommendation
Godot 4.7 stable, GDScript only, Compatibility renderer on PC, with our own threaded chunk mesher. Before committing, spike chunk meshing and frame time on HD 520/620-class hardware. Try godot_voxel only if the mesher is the measured bottleneck and its GDExtension works on 4.7 for Android. Fall back to Luanti if the spike fails.

## Confidence
Medium. Engine facts come from primary docs and release notes. The low-end performance claim rests on one forum post and no benchmark.

## Sources
- https://godotengine.org/news/ (4.7 and 4.7.2 dates)
- https://godotengine.org/releases/4.7/
- https://godotengine.org/article/platform-state-in-csharp-for-godot-4-2/
- https://github.com/godotengine/godot-docs/pull/7551/files
- https://docs.godotengine.org/uk/4.4/_sources/tutorials/rendering/renderers.rst.txt
- https://voxel-tools.readthedocs.io/en/latest/getting_the_module/
- https://github.com/Zylann/godot_voxel
- https://forum.godotengine.org/t/game-performance-on-different-computers/133026
- https://blog.luanti.org/2026/08/21/5.17.0-released/
- https://www.gamingonlinux.com/2026/01/luanti-formerly-minetest-v5-15-brings-ui-improvements-mod-upgrades-and-a-big-performance-boost/
- https://docs.luanti.org/for-creators/mobile/
- https://minecraft.wiki/w/Java_Edition
- https://unity.com/pricing-updates
- https://docs.unity.com/en-us/engine/6000.6/manual/platform-specific/linux.md
- https://bevy.org/news/
- https://bevy.org/learn/migration-guides/0-19-to-0-20/
- https://docs.rs/bevy_android

## Open questions
1. Does Godot 4.7 support C# Android export? Check the current 4.x docs.
2. Measured frame time on HD 520/620 for Compatibility vs Vulkan Mobile (Windows driver support unverified).
3. Is godot_voxel's GDExtension stable on 4.7 and on Android?
4. Godot test framework choice (GUT or GdUnit4) not verified in this scout.
5. Does Luanti's Lua API cope with real-time creature combat at target view distance?
