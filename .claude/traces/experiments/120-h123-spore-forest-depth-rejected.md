# 120 - H123 Spore Forest-Depth Probe Rejected

Date: 2026-07-31
Status: DONE - protected probe tested, rejected, and rolled back

## Purpose

Execute the user-approved H105 Spore forest-depth protected packet, measure it
against the existing H105 gates, and keep it only if the evaluator nominates it
for disjoint-seed confirmation.

## Approval

User explicitly approved editing:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

No YAML, generated DB, schema, AI, difficulty, economy, UI, unlock, or reward
files were approved or edited.

## Source State

- Branch: `main`
- HEAD before implementation: `abd62b6 Map H105 implementation seam`

## Preflight

Command:

```text
python3 scripts/run_h105_spore_forest_workflow.py \
  --execute \
  --skip-self-play \
  --prefix warforge_h123_h105_preflight
```

Results:

```text
PASS codegen parity
PASS card spawn guard
PASS focused Druid runtime tests: 54/54, 173 assertions
PASS focused ChainEngine tests: 21/21, 31 assertions
PASS H105 changed-file boundary: 0 changed files
PASS git diff --check
```

Godot emitted the known macOS certificate startup warning in focused GUT runs:

```text
ERROR: Condition "ret != noErr" is true. Returning: ""
```

It did not fail either suite.

## Test-First Signal

Added focused tests before implementation.

Fail-before Druid runtime:

```text
57/61 passed
4 failing tests
177/182 assertions
```

Fail-before ChainEngine:

```text
21/24 passed
3 failing tests
32/40 assertions
```

Failures were exactly the intended forest-depth assertions: collected Spore
debuffs stayed at old own-tree values.

## Implemented Candidate

Temporary protected edits:

- Added `_SPORE_FOREST_DEPTH_DEBUFF_SCALE := 0.0025`.
- Added non-Spore active Druid tree-depth collection.
- Lifted Spore enemy debuffs at `collect_enemy_battle_debuffs(board)` time.
- Preserved local stored Spore `theme_state["enemy_*_debuff"]` values as
  own-tree-only.
- Preserved Star 3 self shield as own-tree-only.
- Preserved duplicate strongest-effect-wins and the 50% cap.

Focused pass after implementation:

```text
PASS focused Druid runtime tests: 61/61, 182 assertions
PASS focused ChainEngine tests: 24/24, 40 assertions
```

## H105 Workflow

Command:

```text
python3 scripts/run_h105_spore_forest_workflow.py \
  --execute \
  --prefix warforge_h123_h105_spore_forest60
```

Workflow results:

```text
PASS codegen parity
PASS card spawn guard
PASS focused Druid runtime tests: 61/61, 182 assertions
PASS focused ChainEngine tests: 24/24, 40 assertions
PASS same-seed self-play report generated
PASS summary generated
PASS analyzer generated
PASS H105 changed-file boundary: 3 changed files in approved boundary
PASS git diff --check
```

H105 gate evaluator:

```text
Verdict: WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT
Next: Treat as weak local signal; do not adopt without new evidence.

Run Result
- Clears: 9/60 -> 11/60
- Avg final HP: -4.23 -> -2.67 (delta +1.57)
- R9-R11 focus WR: 34.6% -> 42.7% (delta +8.1%)
- Active-loss survivors A/E: 0.0/13.8 -> 0.0/14.2
- H74 screen: WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT

Failed gates
- clears_materially_improve: observed 11, target >=14
- active_loss_enemy_survivors_fall: observed 14.213, target <=12.5
- active_loss_allied_survivors_move: observed 0.0, target >=0.2

Passed gates
- avg_final_hp_improves
- focus_wr_improves
- h74_screen_not_flat
- debuff_too_small_decreases
- not_cap_heavy
```

The patch removed the `debuff_too_small` bottleneck but did not produce enough
run-level movement or survivor-margin movement to pass the packet gates.

## Rollback

Because the evaluator did not nominate the candidate, the protected edits were
rolled back:

```text
git restore \
  godot/core/druid_system.gd \
  godot/tests/test_druid_system.gd \
  godot/tests/test_chain_engine.gd
```

Post-rollback focused tests:

```text
PASS focused Druid runtime tests: 54/54, 173 assertions
PASS focused ChainEngine tests: 21/21, 31 assertions
```

Post-rollback worktree before record files:

```text
clean
```

## New Evidence For Next Slice

The rejected candidate is still diagnostically useful:

- Debuff pressure moved: R9-R11 focus WR improved from 34.6% to 42.7%.
- Survivor margins did not move enough: active-loss allied survivors stayed at
  0.0 and enemy survivors worsened from 13.8 to 14.2.
- Analyzer next signal after debuff lift: damage shortfall dominates; inspect
  Wrath/World offensive battle math.
- Run-phase signal remains timing-sensitive: focus activation often happens in
  the lethal window.
- Activation/promotion audit reports bench/promotion gaps common enough to
  justify a future activation/promotion-policy probe, but only after a fresh
  bounded packet.

## Record-Only Verification

PASS H105 changed-file boundary after rollback and record update:

```text
Result: PASS
Allow records: True
Checked files: 2

Files:
- .claude/traces/experiments/120-h123-spore-forest-depth-rejected.md
- Plans.md
```

PASS whitespace guard:

```text
git diff --check
```

## Decision

REJECT and rollback.

Do not retry this exact Spore forest-depth routing shape without new evidence.
The next M1 strategy-floor slice should start from the H123 analyzer signal:
debuff-only mitigation is insufficient; inspect Druid damage conversion and
payoff activation timing before preparing another protected gameplay packet.
