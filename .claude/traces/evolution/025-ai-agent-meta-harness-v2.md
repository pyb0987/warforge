---
iteration: 25
date: "2026-05-28"
type: additive
verdict: neutral
files_changed: ["spec.md", "Plans.md", "AGENTS.md", "scripts/check_harness_v2_surface.py", ".claude/traces/search-set.md", ".claude/traces/evolution/025-ai-agent-meta-harness-v2.md"]
refs: [24, ".claude/traces/search-set.md", "CLAUDE.md"]
---

## Iteration 025: AI Agent Meta-Harness v2 adapter migration

### Trigger
The project owner requested applying `pyb0987/ai-agent-meta-harness` to
Warforge/chain-army, similar to the CWAA target-project migration.

### Diagnosis
Warforge already has meaningful `.claude/traces/` history:

- 24 prior evolution traces, including Codex routing in iteration 024.
- 11 failure diagnoses.
- Multiple fixed-evaluator/autoresearch experiment episodes.
- Active search-set cases for hook references, evaluator cliffs, genome bounds,
  card design/code mismatch, stale Godot class cache, spawn funnel, and keyword
  glossary drift.

Creating a fresh `.harness/traces/` root would split evidence. The safe
migration is therefore an adapter migration: keep `.claude/traces/` active and
add the v2 contract/plan surface that points back to the existing design memory.

The intended source is the local checkout at
`/Users/fainders/personal/claude-code-harness`, whose origin is
`https://github.com/pyb0987/ai-agent-meta-harness.git`. Its Codex adapter
guidance is `adapters/codex/skills/init-codex-harness/SKILL.md`.

Existing Active search-set commands are legacy shell-style commands. Rather
than rewriting all of them in one harness iteration, this migration adds an
argv-safe `SS-012` for the new v2 surface and records legacy command migration
as backlog.

### Change
- Added `spec.md` as the repo-level harness contract.
- Added `Plans.md` as the active non-trivial work plan.
- Updated `AGENTS.md` to name the AI Agent Meta-Harness source and v2 operating
  surface.
- Kept `.claude/traces/` as the active trace root.
- Added `scripts/check_harness_v2_surface.py` and `SS-012` to verify that the
  v2 surface exists, points to the active trace root, and uses the intended
  harness source.

### Result
- Before: Codex routing existed in `AGENTS.md`, but there was no root
  `spec.md`/`Plans.md` v2 contract surface.
- After: v2 contract/plan surface exists without replacing `DESIGN.md`,
  `CLAUDE.md`, or `.claude` design/trace memory.
- Post-change verification: PASS
  `python3 scripts/check_harness_v2_surface.py`
  - PASS: Warforge AI Agent Meta-Harness v2 surface is coherent.
- Post-change verification: PASS
  `python3 /Users/fainders/personal/claude-code-harness/scripts/run-search-set.py --search-set .claude/traces/search-set.md --cwd . --case SS-012`
  - SS-012 PASS.
  - run-search-set: PASS (1 Active case(s)).
- Focused guard verification: PASS
  `python3 scripts/lint_card_spawn.py`
  - command exited 0.
- Focused guard verification: PASS
  `python3 -m unittest scripts.tests.test_lint_card_spawn`
  - Ran 10 tests in 0.006s, OK.
- Full Active search-set pyb runner: SKIPPED
  `python3 /Users/fainders/personal/claude-code-harness/scripts/run-search-set.py --search-set .claude/traces/search-set.md --cwd .`
  - Existing legacy Active cases use shell syntax and should be migrated to
    argv-safe scripts one case at a time.
- Full GUT suite: SKIPPED
  `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
  - This migration changed only harness docs/check scripts, and the worktree
    already has Godot editor cache changes. Avoided additional cache churn.

### Lesson
When applying `pyb0987/ai-agent-meta-harness` to a project with mature Claude
trace history, preserve the existing trace root first. Migrating legacy
search-set commands to argv-safe scripts should be a separate iteration because
rewriting every Active guard at once would add avoidable confounders.
