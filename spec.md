# Warforge Harness Spec

Status: active
Last updated: 2026-05-28

## Purpose

Warforge uses the `pyb0987/ai-agent-meta-harness` v2 surface as a
target-project operating contract for agent work. This file does not replace
the existing design memory; it points agents to the durable design sources,
trace history, verification gates, and stop conditions that keep changes
reviewable.

## Sources Of Truth

- Design source: `DESIGN.md` and the detailed docs under `docs/design/`.
- Claude project policy and domain contract: `CLAUDE.md`.
- Harness history: `.claude/traces/`, kept as the active trace root because it
  already contains meaningful evolution, failure, experiment, review, and
  search-set history.
- Active task plan: `Plans.md`.
- Fixed-evaluator/search directions: `godot/sim/program.md`,
  `godot/sim/ai_research/ai_program.md`, and
  `godot/sim/cp_formula_research/cp_formula_program.md`.
- Runtime instructions: `AGENTS.md` and `CLAUDE.md`.

## Scope

In scope:

- Use plan -> test/verify -> implement -> record discipline for non-trivial
  changes.
- Preserve the Sprint Contract in `CLAUDE.md` for code, card, number, and
  document changes.
- Keep harness evolution additive first, with one functional harness change per
  iteration.
- Record causal failures, harness changes, and fixed-evaluator episodes under
  `.claude/traces/`.
- Use fixed-evaluator search only when the evaluator, protected files, metric,
  and adoption threshold are explicit.

Out of scope:

- Replacing `.claude/traces/` with `.harness/traces/` without a separate,
  reviewed migration trace.
- Applying unrelated harness distributions or migration commands.
- Editing Tier 0 evaluator/protected files under `godot/sim/` without explicit
  user approval.
- Editing generated `godot/core/data/card_db.gd` directly instead of changing
  YAML/codegen inputs.
- Treating Godot editor cache churn as harness signal unless a trace explicitly
  ties it to a failure.

## Acceptance Criteria

- Agents can identify `.claude/traces/` as the active trace root.
- `Plans.md` captures current non-trivial harness/work plans and status.
- `AGENTS.md`, `spec.md`, and `Plans.md` all point to the same active trace
  root and intended harness source.
- `.claude/traces/search-set.md` keeps executable Active verification cases.
- Any skipped verification is recorded with the exact command and reason.
- Card/code changes respect `DESIGN.md`, relevant `docs/design/` files, and the
  generated-data boundary.

## Verification

Focused harness surface check:

```bash
python3 scripts/check_harness_v2_surface.py
```

Search-set runner for the v2 surface case:

```bash
python3 /Users/fainders/personal/claude-code-harness/scripts/run-search-set.py --search-set .claude/traces/search-set.md --cwd . --case SS-012
```

Focused card spawn guard:

```bash
python3 scripts/lint_card_spawn.py
python3 -m unittest scripts.tests.test_lint_card_spawn
```

Full GUT suite when touching Godot gameplay, card data, or generated code:

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

## AI Agent Meta-Harness Source

This target-project harness is based on the local AI Agent Meta-Harness v2
checkout:

- Source path: `/Users/fainders/personal/claude-code-harness`
- Origin: `https://github.com/pyb0987/ai-agent-meta-harness.git`
- Target-project adapter: `adapters/codex/skills/init-codex-harness/SKILL.md`

The target project does not need the repository-local `governance` CLI copied
into Warforge. The durable Warforge contract remains `AGENTS.md`, `spec.md`,
`Plans.md`, and `.claude/traces/`.

## Stop Conditions

Stop and ask before continuing if:

- `.claude/traces/` and `.harness/traces/` both contain divergent meaningful
  history.
- A change would touch protected evaluator/search files, generated card DB
  output, or Godot editor cache files as part of a harness change.
- A fixed-evaluator attempt needs to alter evaluator closure, oracle material,
  score parsers, or protected baseline data.
- A design/code change contradicts `DESIGN.md` or requires a DESIGN impact-map
  update that has not been reviewed.
