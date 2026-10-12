# M0 report — skeleton and world spike

**Status:** DONE. Performance gate passed on the owner's Vega 8 (D-019). Tagged `m0-done`.

## Summary
A Godot 4.7.2 project with tooling (`setup.sh`, `check.sh`: format, lint, import, GUT, with compile-error detection), typed core interfaces with Gen 2 data contracts, 11 sample species, a threaded voxel world of column chunks, a player with fly mode, a debug overlay, settings, a 60 s benchmark mode, and a Windows export.

## Demo / how to run
Unzip `Minemon-M0-windows.zip`, then:
1. double-click `Benchmark (low-end).bat`, then `Benchmark (Vulkan).bat`;
2. send the two `benchmark_*.txt` files;
3. `Play (low-end).bat` to walk around (WASD, mouse, Space, F fly, F3 overlay).

## Test evidence
- check.sh: 144 tests, 0 failures.
- Headless (2 cores): avg 145 fps, 1% low 78 fps, worst frame 26 ms, static memory 45 MB.
- Streamer main thread: p99 4.3 ms, max 7.7 ms.

## Tasks
6 tasks done (T-01..T-06).
- First-pass verification: 2/6 (T-04, T-06).
- Retries: T-01 (silent compile errors), T-02 (Gen 2 data), T-03 (winding, free crash, stale mesh, speed), T-05 (unwaited tasks).
- T-06 was added after the T-05 profiling.

## Decisions / deviations
D-015..D-018. Records are split one file per class; terrain uses GDScript noise.

## Risks
- Real Vega 8 numbers are unknown, as is the old 2021 driver.
- Initial world fill is slow on 2 cores.
- Base exp values are modern.

## Lessons
See docs/LESSONS.md, entries dated 2026-10-10.

## Next
- Owner runs the benchmarks.
- If they pass: pick the default renderer (D-entry), tag m0-done, start M1 (combat core).
- If they fail: try the BACKLOG performance candidates, then reconsider Luanti (D-015).
