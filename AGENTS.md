# Warforge — Codex Project Instructions

## Build

```bash
# GDScript unit tests (GUT v9.6.0), full directory
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit

# Single GDScript test file
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_X.gd -glog=1 -gexit

# Fresh worktree / CI cache rebuild before tests when class_name cache may be stale
rm -f godot/.godot/global_script_class_cache.cfg
godot --headless --path godot/ --import

# Python guard for card spawn funnel
python3 scripts/lint_card_spawn.py
python3 -m unittest scripts.tests.test_lint_card_spawn
```

## Architecture

- Warforge is a trigger-chain roguelike deckbuilder built in Godot 4 with Python simulator/tooling support.
- `DESIGN.md` is the top-level truth source. Detailed design docs live under `docs/design/` and must not contradict `DESIGN.md`.
- Core Godot autoloads include Enums, CardDB, UnitDB, and UpgradeDB. Core systems include chain_engine and combat_engine.
- For card/code changes, read the matching design document before editing. Do not implement from memory or context summaries when exact timing/effect values matter.
- Card data source is YAML plus codegen. Do not edit generated `card_db.gd` directly.

## Harness

### V2 Operating Surface

- This project uses `pyb0987/ai-agent-meta-harness` via the local checkout at `/Users/fainders/personal/claude-code-harness`.
- Treat `spec.md` as the repo-level harness contract and `Plans.md` as the active non-trivial work plan.
- These files do not replace design memory; they point to `DESIGN.md`, `CLAUDE.md`, `docs/design/`, and `.claude/traces/`.
- Do not apply unrelated harness distributions or migration commands unless the user explicitly asks for that toolchain.

### Agent Routing

Users do not need to name harness skills. Route ordinary requests by intent:

- "Apply meta-harness to this project" or "set up agent memory/traces" means initialize or update this project harness.
- "This keeps failing", "stop repeating this", or "make this not happen again" means inspect raw traces and evolve the harness before another retry.
- "Review this carefully", "am I missing anything?", or other high-stakes judgment requests mean use multi-perspective review when it materially reduces risk.
- "Try variants", "optimize this", or "keep the measurable winner" means propose an autoresearch loop only when a fixed evaluator and clear metric exist.

For ordinary feature work, work normally. Escalate only when the request or evidence matches one of the routing signals above.

### Trace Root

Use `.claude/traces/` for harness history because this project already has meaningful trace history:

```text
.claude/traces/evolution/     # Harness change history
.claude/traces/failures/      # Failure diagnosis with raw context
.claude/traces/experiments/   # Autoresearch episodes
.claude/traces/search-set.md  # Active verification cases
```

### Change Strategy

Use additive changes first, subtractive changes second, structural changes last. Keep one functional harness change per iteration so regressions are attributable.

### Verification

Before and after harness changes, run Active verify commands from `.claude/traces/search-set.md` when practical. Record PASS/FAIL and key output lines in the related evolution trace.

For code changes, use the Sprint Contract from `CLAUDE.md`: cards/numbers require full GUT test pass, document changes require DESIGN impact-map sync, and new implementation defaults to Plan -> Test -> Implement.

### Failure Recording

Record failures that require causal reasoning, produce results opposite to hypothesis, or reveal a new guard violation type. Do not record simple typos or obvious one-off fixes.

### Structural Escalation

Recurring failures should move from instructions to tooling, CI, generated artifacts, or other structural prevention. Prefer "cannot happen" over "remember not to do it."

## Codex Notes

- Codex does not run Claude Code hooks from `.claude/settings.local.json`. Treat hook descriptions as policy history and run explicit verification commands.
- Tier 0 protected evaluator files under `godot/sim/` are not agent-writable without explicit user approval.
- `card_db.gd` is generated output; change YAML/codegen inputs instead.
- If verification is skipped because Godot is unavailable, sandboxing blocks execution, or a command is too expensive, record SKIPPED with the exact reason and rerun command instead of treating it as PASS.
