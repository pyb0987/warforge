# Experiment 100 - AI Active-Slot Focus Semantics

Date: 2026-07-31
Status: DONE - kept as correctness cleanup, not a gameplay-power improvement

## Decision

Keep the user-approved `godot/sim/ai_agent.gd` and
`godot/tests/test_ai_agent.gd` change that makes the AI's `_active_board_ids`
helper count only cards inside the currently usable `field_slots`.

This closes a narrow semantic bug in Druid path-focus promotion: a payoff card
parked in a non-usable board index could be mistaken for an active payoff, so a
bench copy would not be promoted into the active field.

Do not claim this as a Druid balance improvement. Same-seed self-play and trace
comparison were flat against H94.

## Approved Scope

The user explicitly approved edits to:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

No card YAML, generated card DB, difficulty values, economy values, upgrade
values, or other protected tuning surfaces were edited.

## Implementation

- Added `test_druid_path_focus_ignores_cards_outside_field_slots`.
- Changed `AIAgent._active_board_ids(state)` to iterate `state.field_slots`
  instead of every non-null `state.board` slot.

The helper is used by AI promotion/path tracing. Its local meaning now matches
the promotion contract already used by `_find_path_focus_replacement`, which
only considers indices inside `state.field_slots`.

## Regression Evidence

Pre-fix focused AI test:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

39/40 passed.
Failed: test_druid_path_focus_ignores_cards_outside_field_slots
- bench payoff stayed on bench
- no dr_spore_cloud existed inside usable field slots
```

Post-fix focused AI test:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

40/40 passed.
```

Whitespace guard:

```text
git diff --check -- godot/sim/ai_agent.gd godot/tests/test_ai_agent.gd

PASS
```

Card spawn guard:

```text
python3 scripts/lint_card_spawn.py

PASS
```

Full GUT suite:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h103_full \
  godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ -glog=1 -gexit

Scripts 57
Tests 1283
Passing Tests 1283
Asserts 9276
```

## Same-Seed Self-Play Screen

Patched working-tree run:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h103_active_slots60 \
  godot --headless --log-file /private/tmp/warforge_h103_active_slots60.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=60 --strategies=soft_druid --difficulty=1 \
  --commander=gambler --talisman=flint \
  --seed=2026072901 \
  --out=/private/tmp/warforge_h103_active_slots60.json \
  --trace-dir=/private/tmp/warforge_h103_active_slots60_traces \
  --quiet-progress=true
```

Source state:

- Commit: `12894678871a6c0ef4a185a7e2c9c4d80fa84e16`
- Branch: `main`
- Dirty: `true`
- Dirty files:
  - `godot/sim/ai_agent.gd`
  - `godot/tests/test_ai_agent.gd`

Summary:

- 9/60 clears (15.0%)
- Avg final HP: -4.23
- Completion readiness: `needs_attention`
- Main warning still `low_overall_clear_rate`

Analyzer comparison against H94:

```text
run result: 9/60 -> 9/60 clears (Delta +0)
avg HP: -4.23 -> -4.23 (Delta +0.00)
R9-R11 focus ledger: WR 34.6% -> 34.6% (Delta +0.0%)
bottleneck deltas: all 0
activation/promotion deltas: all 0
screen verdict: REJECT_FLAT_OR_NOISY
```

The current R9-R11 gameplay bottleneck remains:

```text
primary bottlenecks: {'debuff_too_small': 30, 'debuff_missing': 15,
  'enemy_pressure_spike': 6, 'damage_shortfall': 1,
  'board_mass_shortfall': 1}
next signal: Spore is present but under-moving enemy pressure; inspect Spore
debuff scaling/caps.
```

## Multi-Review

Three independent reviewers returned `KEEP`, with the same caveat:

- Correctness semantics: `_active_board_ids` is an AI helper for usable active
  field slots; the regression test captures the intended semantics.
- Gameplay adoption: do not claim a Druid-power improvement because the
  same-seed screen is numerically flat.
- Protected-scope/release risk: keep within the approved two-file scope and
  record the trace as correctness cleanup, not balance tuning.

Residual risk carried forward:

- `GameState.get_active_board()` still returns every non-null board card. This
  may be intentional in the broader engine, but it should be separately defined
  or verified before changing combat/reward behavior outside the approved AI
  surface.

## Next Slice

Pause after this run as requested.

When work resumes, do not continue from this cleanup as if it solved Druid
viability. H102 remains the likely gameplay slice: R9-R11 Druid combat
conversion, especially Spore pressure/debuff conversion. Card values,
difficulty, economy, and new `godot/sim/**` policy changes still require fresh
approval before editing.
