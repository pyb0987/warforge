# 124 - H126 Druid Contribution Observability

Date: 2026-07-31
Status: DONE - snapshot contract added; trace emission deferred

## Purpose

H125 showed that immediate Druid AI promotion was not justified. The missing
evidence was runtime contribution: when Spore plus Wrath/World is active and
still loses, are the losses caused by unit mass, buff math, survival, attack
interval timing, or a late arrival?

H126 establishes the Druid-owned combat snapshot contract without touching
protected simulator trace emission.

## Scope

Edited:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`
- `docs/tools/self-play-observer.md`
- `Plans.md`
- `.claude/traces/experiments/124-h126-druid-contribution-observability.md`

Not edited:

- `godot/sim/headless_runner.gd`
- Druid YAML
- generated card DB
- difficulty/economy files
- AI purchase or board activation logic

## Multi-Review

Decision under review:

```text
Add a behavior-neutral Druid combat snapshot helper in the approved Druid
runtime/test files before editing protected simulator trace emission.
```

Critic A, scope boundary:

```text
score: 9
verdict: PASS
finding: a read-only Druid-owned helper in `godot/core/druid_system.gd` is in
scope, provided it does not touch simulator files, YAML, generated DB,
economy/difficulty, or gameplay behavior.
caveat: do not claim trace completion until a permitted caller emits the
snapshot.
```

Critic B, schema/stat fidelity:

```text
score: 6
verdict: VETO
finding: a totals-only schema can false-green future gameplay; stack-level
materialization rows and explicit attack-interval semantics must be mandatory.
required fields: base attack interval, upgrade/unique/temp AS multipliers,
final attack interval, stack ATK/HP/DPS, enemy debuffs, World unique layer,
Wrath temp/mechanic state.
```

Critic C, tests/false-green:

```text
score: 7
verdict: MIXED
finding: field-presence tests are insufficient.
required tests: read-only behavior, formula parity with `CardInstance`
effective stats, temp AS coverage, non-Druid exclusion, and ChainEngine debuff
parity.
```

Synthesis:

```text
ADOPT_HELPER_WITH_STRONG_SCHEMA
Do not implement a totals-only helper.
Do not wire simulator traces without explicit protected-file approval.
```

## Implementation

Added `DruidSystem.build_combat_snapshot(board)`.

The helper is read-only and returns:

- aggregate forest depth, Druid card count, Druid unit count, total ATK, total
  HP, and total DPS.
- aggregated enemy debuffs from existing Spore state.
- per-card rows: index, base id, star, trees, units, ATK/HP/DPS totals, growth
  layers, World unique layer, AS multipliers, shield, Spore debuffs,
  kill-recovery percent, materialized mechanics, and stack rows.
- per-stack rows: unit id/count, effective ATK/HP from `CardInstance`,
  base attack interval, upgrade/unique/temp AS multipliers, final attack
  interval, ATK/HP/DPS totals, range, move speed, and card DEF.

Attack speed is recorded as attack interval because the combat engine treats
lower values as faster attacks.

## Tests Added

Focused Druid tests now verify:

- non-Druid cards are excluded while Spore enemy debuffs are still reported.
- base Druid identity is preserved after a theme transform.
- per-stack ATK/HP and attack interval match the materialization formula:
  `unit.attack_speed * upgrade_as_mult * unique_as_mult * temp_as_mult`.
- card and snapshot totals equal the sum of stack rows.
- repeated snapshots are stable and do not mutate board/card state.
- Wrath kill recovery appears as the materialized mechanic.

Focused ChainEngine test verifies:

- snapshot enemy debuff aggregate matches the debuff dictionary applied by
  `ChainEngine.apply_enemy_battle_debuffs`.

## Verification

PASS focused Druid tests:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_druid_system.gd -glog=1 -gexit
58/58 passed
```

PASS focused ChainEngine tests:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit
22/22 passed
```

PASS full GUT:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ -glog=1 -gexit
Scripts: 57
Tests: 1297
Passing Tests: 1297
Asserts: 9499
```

PASS card spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

PASS diff whitespace:

```text
git diff --check
```

## Decision

H126 is accepted as a behavior-neutral snapshot contract.

It is not yet self-play trace evidence. The next slice is H127:

```text
Wire `DruidSystem.build_combat_snapshot(board)` into the headless battle trace
at the post-persistent/post-battle-start, pre-combat seam, then extend analyzer
logic to read those emitted snapshots.
```

H127 requires explicit approval before editing:

- `godot/sim/headless_runner.gd`
- likely `godot/tests/test_headless_runner.gd`

## Forbidden Follow-Up

Do not use H126 alone to justify Druid gameplay tuning. It only defines and
tests the snapshot contract. Any gameplay packet still needs emitted trace
data, analyzer evidence, and multi-review before adoption.
