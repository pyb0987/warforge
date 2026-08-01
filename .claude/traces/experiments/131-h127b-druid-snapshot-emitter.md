# 131 - H127B Druid Snapshot Emitter

Date: 2026-08-01
Status: PASS

## Purpose

Wire the existing H126/H127B2 read-only Druid combat snapshot into headless
self-play battle traces so Druid Spore plus Wrath/World losses can be
attributed from real trace evidence.

This is observability only. It must not alter gameplay, AI choices, RNG flow,
combat setup, evaluator metrics, settlement, economy, difficulty, card data, or
Druid runtime behavior.

## Implementation

Changed only the approved runner surface plus record files:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`
- `Plans.md`
- `docs/tools/self-play-observer.md`
- `.claude/traces/experiments/131-h127b-druid-snapshot-emitter.md`

Runner behavior:

- Captures `DruidSystem.build_combat_snapshot(active_board)` only when
  `_tracer != null and _tracer.enabled`.
- Captures after persistent effects, battle-start effects, active-board combat
  temp buffs, and Druid enemy battle debuffs.
- Captures before `clear_temp_buffs()` and `shield_hp_pct = 0.0`.
- Adds the canonical `druid_combat_snapshot` key to battle events only when the
  snapshot contains at least one Druid card.
- Routes battle event emission through a small helper used by the real run path.

Focused regression:

- Proves the battle event uses `druid_combat_snapshot`.
- Checks H126-shaped top-level fields, `enemy_debuffs`, and card rows.
- Checks Spore aggregate and card-row debuffs.
- Checks Wrath/World offensive rows with nonzero units, ATK, HP, DPS, stacks,
  and final attack interval.
- Proves captured pre-cleanup temp/shield data survives even after live card
  cleanup.
- Proves disabled tracing skips snapshot construction.
- Proves tracing on/off same-seed core runner metrics are unchanged.

## Verification

H127B workflow:

```text
python3 scripts/run_h127b_emitter_workflow.py --execute --prefix=warforge_h127b_druid_emitter60_h131
```

Result: PASS

Key workflow steps:

- PASS H127B changed-file boundary.
- PASS focused HeadlessRunner tests: 18/18.
- PASS focused Druid snapshot tests: 60/60.
- PASS Druid contribution analyzer tests: 31/31.
- PASS fresh soft-Druid self-play traces: 60 runs, D1, gambler/flint.
- PASS Druid contribution readiness gate.
- PASS diff whitespace check.

Readiness gate output:

```text
Result: PASS
Trace dir: /private/tmp/warforge_h127b_druid_emitter60_h131_traces
Strategy: soft_druid
Scope: R9-R11
Snapshot coverage: 111/111 (100.0%)
Focus coverage: 100.0%; valid 73; missing 0; invalid 0
Spore+offense frames: 11
Spore+offense losses: 8
Next signal: PAIR_CONTRIBUTION_TRACE_READY: Spore+Wrath/World losses now have per-card/per-stack contribution facts; use this before gameplay.
```

Additional verification:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result: PASS, 1304/1304.

```text
python3 scripts/lint_card_spawn.py
python3 -m unittest scripts.tests.test_lint_card_spawn
```

Result: PASS, guard silent; unit tests 10/10.

## Fresh Evidence

Trace summary:

- soft-Druid clear rate: 4/60 (6.7%).
- Average rounds reached: 10.53.
- Main loss rounds: R9 x15, R10 x12, R8 x9, R11 x7, R13 x7.
- Completion readiness still needs attention due to low overall clear rate and
  weak strategy floor.

Druid contribution ledger:

- 73 Druid-focus snapshot frames in R9-R11.
- Snapshot coverage is now complete for the in-scope sample.
- Runtime buckets: `missing_spore`: 19, `missing_offense`: 23,
  `pair_no_ally_survival`: 8.
- Pair losses now have per-card/per-stack facts:
  - average Spore debuff ATK/AS: 3.2% / 19.4%
  - average offense units: 3.0
  - average offense ATK/HP/DPS: 47.0 / 346.9 / 48.5
  - average final interval: 1.07
  - average survivors in pair losses: ally 0.0 / enemy 15.8

## Decision

ADOPT H127B.

The next gameplay slice should use the H127B contribution ledger before changing
AI, Druid runtime balance, card data, economy, difficulty, or evaluator logic.
Do not treat this slice as a Druid viability fix; it is the observability needed
to choose the next fix honestly.
