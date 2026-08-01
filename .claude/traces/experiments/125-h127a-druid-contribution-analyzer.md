# 125 - H127A Druid Contribution Analyzer

Date: 2026-07-31
Status: DONE - analyzer consumer added; protected emitter still pending

## Purpose

H126 defined a read-only Druid combat snapshot contract in Godot, but existing
self-play traces do not emit it. H127A adds the analyzer-side consumer first so
the eventual protected trace-emitter patch has an executable target and current
traces fail honestly on missing contribution evidence.

## Scope

Edited:

- `scripts/analyze_ai_trace.py`
- `scripts/tests/test_analyze_ai_trace.py`
- `docs/tools/self-play-observer.md`
- `Plans.md`
- `.claude/traces/experiments/125-h127a-druid-contribution-analyzer.md`

Not edited:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`
- Druid runtime/card YAML/generated DB
- gameplay balance, AI purchase, economy, or difficulty logic

## Implementation

Added `--druid-contribution-ledger` to `scripts/analyze_ai_trace.py`.

The ledger reads future battle events with:

```text
druid_combat_snapshot
```

It also accepts `druid_snapshot` as a compatibility alias.

The analyzer summarizes R9-R11 Druid focus snapshot frames by:

- snapshot coverage across in-scope battles.
- missing focus snapshots when round-end data shows Druid focus cards active
  but battle events lack the H126 snapshot.
- invalid focus snapshots when emitted data lacks required H126 top-level,
  per-card, or per-stack fields.
- Spore+Wrath/World pair frames and losses.
- Spore ATK/AS debuffs from the top-level `snapshot.enemy_debuffs` aggregate.
- Wrath/World offense units, ATK, HP, DPS, and weighted final attack interval
  from per-stack `final_attack_interval`.
- runtime buckets for observed losses:
  - `missing_spore`
  - `missing_offense`
  - `pair_no_ally_survival`
  - `pair_no_offense_dps`
  - `pair_unconverted_enemy_margin`
  - `pair_unknown_loss`

This is diagnostic only. It does not introduce adoption thresholds or gameplay
recommendations.

## Tests Added

Python analyzer tests cover:

- full H126-shaped `druid_combat_snapshot` data with active Spore+Wrath pair
  loss.
- per-stack weighted attack-interval aggregation.
- top-level Spore debuff and Wrath offense contribution fields.
- explicit `SNAPSHOT_EMISSION_REQUIRED` when current-style traces show Druid
  focus battles but no contribution snapshot.
- explicit `SNAPSHOT_SCHEMA_INVALID` when a focus battle emits a malformed
  snapshot.
- protection against reading base attack interval instead of
  `final_attack_interval`.
- scalar-type rejection for H126 fields: non-string IDs, non-integer counters,
  booleans, non-finite numbers, and stringified numeric combat fields.

## Verification

PASS analyzer tests:

```text
python3 -m unittest scripts.tests.test_analyze_ai_trace
Ran 31 tests
OK
```

PASS syntax:

```text
python3 -m py_compile scripts/analyze_ai_trace.py
```

PASS current-trace CLI smoke:

```text
python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h104_clean_druid60_traces \
  --strategy=soft_druid \
  --druid-contribution-ledger
```

Key output:

```text
snapshot coverage: 0/129 in-scope battles (0.0%)
focus coverage 0.0%
missing focus snapshots 81
invalid snapshots 0
invalid focus snapshots 0
next signal: SNAPSHOT_EMISSION_REQUIRED
```

## Multi-Review

Initial contract-fidelity review returned VETO because the first analyzer draft
read Spore debuffs from per-card fields and allowed incomplete snapshots to
look contribution-ready.

Fixes applied:

- read Spore ATK/AS from top-level `snapshot.enemy_debuffs`.
- require H126 top-level, per-card, and per-stack fields before counting a
  snapshot as valid evidence.
- classify present-but-malformed snapshots as `SNAPSHOT_SCHEMA_INVALID`.
- keep no-snapshot current traces on `SNAPSHOT_EMISSION_REQUIRED`.
- test malformed snapshots with and without a `cards` field.
- test wrong scalar values such as string counters, non-finite totals, boolean
  debuffs, numeric card IDs, fractional stack counts, and string intervals.
- make base and final attack intervals differ in the positive fixture.

Rerun verdicts:

- Contract fidelity: PASS.
- False-green/scope boundary: PASS.

## Decision

Accept H127A as analyzer-side support only.

Do not use H127A output on old traces as Druid gameplay evidence. Its current
value is that it proves the next concrete gap:

```text
H127B must emit `DruidSystem.build_combat_snapshot(board)` from the protected
headless battle trace seam before contribution analysis can inform gameplay.
```

H127B requires explicit approval before editing:

- `godot/sim/headless_runner.gd`
- likely `godot/tests/test_headless_runner.gd`

## Forbidden Follow-Up

Do not tune Druid combat from `--druid-contribution-ledger` until traces show
nonzero snapshot coverage from real self-play runs. Missing-snapshot output is
an observability readiness signal, not a balance signal.
