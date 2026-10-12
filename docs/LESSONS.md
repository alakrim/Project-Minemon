# Lessons

- 2026-10-10: Agent definitions in `.claude/agents/` load at session start only. A new definition is not usable in the session that creates it; spawn `general-purpose` with `model: haiku` meanwhile.
- 2026-10-10: Scouts counted tables/sources toward word limits inconsistently; briefs should say "sections only, max N words".
- 2026-10-10: GUT silently drops test scripts that fail to compile; check.sh must scan the GUT log for SCRIPT ERROR/Parse Error. Always include a compile-error adversarial test when verifying test tooling.
- 2026-10-10: Face-count tests could not catch inverted triangle winding; rendering defects need a render or winding test. The verifier's Xvfb render check found it.
- 2026-10-10: Worker-thread tasks bound to Callable(node) lock the Node, so free() is refused. Run jobs on a RefCounted runner.
- 2026-10-10: check.sh must exclude .claude/worktrees/ when parallel worktree builds exist.
- 2026-10-10: Headless benchmarks using engine delta hide spikes; always measure wall-clock (Time.get_ticks_usec). Profile main-thread costs before shipping a perf build.
- 2026-10-10: Pushing git tags is refused by the session proxy (403). Milestones are marked in docs/milestones and PROGRESS; tags stay local.
- 2026-10-10: A worker's `git rm -r` of archived files was refused by the auto-mode safety check. Briefs should avoid bulk deletions; prefer leaving files or overwriting them, or get explicit owner approval.
- 2026-10-10: Parallel worktrees shared .tools/games through the .tools symlink, so check.sh runs overwrote each other's assembled game. The games dir is now per-checkout (.games/).
- 2026-10-11: Owner feedback: too slow. Run fewer verification loops for low and medium risk, take shortcuts first (a scout per wave), and deliver playable builds early.
- 2026-10-11: Workers follow the harness attribution reminder (Haiku trailer) over the brief's trailer. Briefs should not dictate the Co-Authored-By line.
- 2026-10-11: Wave 1 (3 high/medium tasks) to a merged, verified build took about 1 hour: briefs that fix file ownership, plus one cross-mod verifier instead of per-task verifiers, worked well. Keep this shape.
- 2026-10-11: Parallel worktree test runs collided on ports; the runners now pick random free ports (T-28b).
