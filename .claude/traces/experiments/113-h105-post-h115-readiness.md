# 113 - H105 Post-H115 Readiness

Date: 2026-07-31
Status: DONE - approval-first readiness handoff

## Purpose

Resume the game-completion goal after H115 and decide the next slice without
mistaking easy side work for M1 progress.

The active M1 blocker remains the strategy viability floor. Current evidence
points to H105, a protected runtime-only Druid Spore forest-depth routing probe.
The user approval currently covers only AI files, so H105 implementation still
requires fresh explicit approval for its protected Druid file set.

This trace records routing and readiness only. It does not implement H105.

## Advisory Multi-Review

Decision under review: choose the next autonomous development slice after H115.

Critics:

- Completion-Criticality Critic: verdict `BLOCKED_ON_H105_APPROVAL`.
- Scope-Boundary and Safety Critic: verdict `NO_CODE_EDIT_UNTIL_H105_APPROVAL`.
- Player-Facing Gap Critic: verdict `ADVISORY_PRIORITIZE_H105_APPROVAL`;
  fallback was a narrow live SELL matrix for Hoarder/Awakening if non-protected
  player-facing work is needed.

Synthesis:

- H105 approval is the next completion-critical step.
- Another AI-only Druid slice would likely retread flat/rejected evidence unless
  a new isolated AI defect is found.
- Another live-smoke slice can improve playtest confidence but should not be
  counted as strategy-floor progress.
- Do not edit protected H105 files until the user explicitly approves them.

## Source State

- Branch: `main`
- HEAD before preflight: `cfaeb6c Cover live Masquerade sell flow`
- Worktree before preflight:

```text
## main...origin/main
```

## Command

```text
python3 scripts/run_h105_spore_forest_workflow.py \
  --execute \
  --skip-self-play \
  --prefix warforge_h116_h105_preflight
```

`--skip-self-play` keeps this pass to pre-implementation readiness checks. It
does not regenerate outcome evidence or evaluate H105 adoption gates.

## Results

PASS source state:

```text
## main...origin/main
```

PASS codegen parity:

```text
card_db.gd + card_descs.gd + conscript_pool_data.gd match YAML (68 cards)
```

PASS card spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

PASS focused Druid runtime tests:

```text
test_druid_system.gd
54/54 tests
173 assertions
```

PASS focused ChainEngine tests:

```text
test_chain_engine.gd
21/21 tests
31 assertions
```

PASS H105 changed-file boundary:

```text
Result: PASS
Allow records: True
Checked files: 0
```

PASS whitespace guard:

```text
git diff --check
```

Godot emitted the known macOS system certificate startup warning in both focused
GUT runs:

```text
ERROR: Condition "ret != noErr" is true. Returning: ""
```

It did not fail either suite.

## Boundary

No gameplay files were edited by this readiness pass.

The protected H105 implementation files remain untouched:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Record-only files for this trace:

- `Plans.md`
- `.claude/traces/experiments/113-h105-post-h115-readiness.md`

## Approval Request For Next Slice

Approve H105 edits limited to:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Scope of the approved probe would be:

- Implement runtime-only Spore forest-depth routing.
- Keep bases, own-tree scaling, caps, YAML, generated DB, schema, AI,
  difficulty, economy, UI, unlocks, and rewards unchanged.
- Verify with the H105 workflow runner, evaluator, boundary guard, focused GUT,
  and full GUT before adoption.

## Decision

ADOPT as H116 readiness evidence.

The next completion-critical implementation remains H105 and should begin only
after explicit protected-file approval.
