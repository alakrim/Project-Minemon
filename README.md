# Project Minemon: rules and status

This repo is the **complete Minemon project**: game code, tools, tests, full git history (imported from alakrim/Minemon), and the project memory (rules, decisions, state).

Minemon is a private Pokémon-like horror adventure. It is built on Luanti 5.17.0 and VoxeLibre 0.92.3, with our own Lua mods. It has real-time creature combat, capture after defeat, 3 lives then permadeath, Kanto and Johto towns, and eldritch giants.

## Continue in a new session
1. Clone this repo. Then run `bash scripts/setup.sh --client`. It takes about 10 minutes and builds Luanti 5.17.0, clones VoxeLibre and cobblemon-bedrock into `.tools/` (git-ignored), and converts the creature models.
2. Run `bash scripts/check.sh`. It runs luacheck, the busted unit tests and 15 headless integration suites, all green at M2.
3. The orchestrator (Opus) reads PROJECT_INSTRUCTIONS.md, docs/PROTOCOL.md, docs/STATE.md (the "Next action" section) and the docs/PROGRESS.md summary, then writes the next briefs in `tasks/M3/` and dispatches Haiku workers (`.claude/agents/worker.md`).
4. Build for Windows with `MINEMON_VERSION=M3 bash scripts/build_windows.sh`. It produces 25 MB parts and a JUNTAR-JOIN .bat in `builds/`.

Note: the abandoned Godot prototype (D-024/D-025) was removed on 2026-10-12. Its history stays in git. The game is `mods/minemon/` on Luanti.

## Rules
- [PROJECT_INSTRUCTIONS.md](PROJECT_INSTRUCTIONS.md): roles (Opus orchestrates, Haiku workers on high effort, no Sonnet), the goal, and working rules.
- [CLAUDE.md](CLAUDE.md): repo guide and the hard content rule.
- [docs/PROTOCOL.md](docs/PROTOCOL.md): how work flows: briefs, workers, verification, commits.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md): code and test conventions.
- [docs/DECISIONS.md](docs/DECISIONS.md): every decision, D-001 to D-031 (append-only).
- [.claude/agents/worker.md](.claude/agents/worker.md): the worker agent definition.

## Status (2026-10-12)
- **Delivered:** M0 (base), M1 (creatures, combat, party, lives, Cobblemon models), **M2 (capture and growth)**.
- **M2 contents:**
  - capture: thrown balls, catch odds, shakes, an enraged break-free;
  - growth: exp, levels, moves, bond and evolution, with a dark cinematic, stones and a Link Cable;
  - **Sanctuaries** (Pokémon Centers as warded lantern shrines with heal, respawn, PC and shop);
  - coins that drop on death;
  - a move command bar;
  - the status-move pass;
  - **Dread variants**: rare corrupted night forms with shards and the Umbral Ball.
- **Next:** the owner playtests M2, then M3 (dread and atmosphere). Pending owner decision: whether to use Cobblemon cries, ball sounds and ball models (D-031).
- Details: [docs/STATE.md](docs/STATE.md), [docs/PROGRESS.md](docs/PROGRESS.md), [docs/PLAN.md](docs/PLAN.md), [docs/BACKLOG.md](docs/BACKLOG.md), [docs/LESSONS.md](docs/LESSONS.md), [tasks/BOARD.md](tasks/BOARD.md), [tasks/M2/](tasks/M2) (briefs and reports), [docs/research/](docs/research) (scout digests).
