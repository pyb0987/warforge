# 129 - H127B2 Druid Snapshot Layer Hardening

Date: 2026-08-01
Status: DONE - behavior-neutral contract hardening

## Context

The user explicitly approved editing:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Multi-review converged that value-changing Druid gameplay work would be false
progress before H127B emits real self-play contribution snapshots. The
frame-challenge critic identified one safe use of the approval: strengthen the
existing read-only Druid snapshot contract so future emitted traces can
distinguish common tree-combat conversion, Wrath flat ATK, temp ATK/HP
multipliers, World unique layers, and attack interval.

## Scope

Edited:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `docs/tools/self-play-observer.md`
- `Plans.md`
- `.claude/traces/experiments/129-h127b2-druid-snapshot-layer-hardening.md`

Not edited:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`
- `godot/tests/test_chain_engine.gd`
- Druid YAML
- generated card DB
- AI policy
- economy, difficulty, combat loop, or evaluator files

## Multi-Review Synthesis

- Critic A: VETO Druid gameplay patch now; H127B trace emission remains the
  honest completion step.
- Critic B: VETO claiming H127 evidence from Druid-side edits; correct evidence
  layer is fresh headless traces plus analyzer/readiness gates.
- Critic C: CONDITIONAL GO for small Druid-side contract hardening only; VETO
  balance, power, activation, acquisition, economy, or difficulty changes before
  H127B.

Decision: implement only behavior-neutral snapshot-layer hardening and do not
claim strategy-floor progress.

## Implementation

`DruidSystem.build_combat_snapshot(board)` now includes:

- per-card `tree_combat_bonus_pct`.
- per-card `temp_atk_flat_total`.
- per-card `temp_atk_mult_min/max`.
- per-card `temp_hp_mult_min/max`.
- per-stack `upgrade_atk_mult` and `upgrade_hp_mult`.
- per-stack `unique_atk_mult` and `unique_hp_mult`.
- per-stack `temp_atk`, `temp_atk_mult`, and `temp_hp_mult`.

No combat state is changed. The helper remains read-only.

## Test-First Evidence

Fail-before focused Druid run:

```text
58/60 passed
2 failing tests
```

Failures were the intended missing snapshot fields:

- `tree_combat_bonus_pct`
- temp ATK/HP layer fields

PASS after implementation:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h128_druid2 \
  godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_druid_system.gd -glog=1 -gexit
```

Observed: `60/60 passed`, `213` assertions.

PASS ChainEngine parity:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h128_chain2 \
  godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit
```

Observed: `22/22 passed`, `33` assertions.

PASS whitespace:

```text
git diff --check
```

PASS card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

PASS full GUT:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h128_full \
  godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ -glog=1 -gexit
```

Observed: `1299/1299 passed`, `9516` assertions.

## Decision

Adopt the snapshot-layer hardening.

This still does not complete H127B. The next completion-critical step remains
approval and implementation for:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`
