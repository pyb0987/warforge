# 101 - Druid Spore Tree-Gap Audit

## Intent

Finish one autonomous run after H103 by improving observability, not gameplay
behavior. H100/H103 kept Druid outcomes flat after protected AI probes, and the
current R9-R11 ledger still points at Spore-present combat conversion. Before
touching protected card/runtime behavior, measure whether Spore's own tree
counters are actually lagging behind the total active Druid forest.

## Multi-Review

Three independent reviewers converged on `ANALYZER_FIRST`:

- Card-design critic: forest-depth Spore is plausible, but a direct protected
  probe risks another H72/H75-style false green unless own-vs-total tree gap is
  systemic.
- Measurement critic: require behavior-neutral own/total tree counters,
  bottleneck cross-tabs by forest-depth band, and diagnostic counterfactuals
  before any packet.
- Implementation critic: keep this slice limited to
  `scripts/analyze_ai_trace.py`, `scripts/tests/test_analyze_ai_trace.py`,
  docs, trace, and plan; do not pass board into Druid runtime yet.

## Changes

- Added `--druid-spore-tree-gap` to `scripts/analyze_ai_trace.py`.
- Reused the existing R9-R11 active ledger frame collector so the new audit
  examines the same focus-active combats as `--druid-active-ledger`.
- The new report prints:
  - Spore own trees vs total active Druid tree counters.
  - Other-Druid tree counters and own/total ratio.
  - Focus-loss bottleneck cross-tabs by active forest-depth band.
  - A diagnostic-only counterfactual that adds non-Spore Druid tree depth at
    `0.0025` per tree, capped at `50%`, solely to estimate whether a protected
    forest-depth probe might cross the existing `20%` low-debuff threshold.
- Added focused Python coverage and docs.

Trace limitation: the current trace stores card state by card ID, so duplicate
copies can collapse; buy events also do not include per-card tree counters. This
audit is aggregate evidence, not per-instance causality.

## Current Evidence

Source before the slice was clean `main` at
`44d91060bf8768cdd4e3d63b1ed19ba29a5f611e`.

Fresh same-seed Druid screen from the current state:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h104_clean_druid60 godot --headless --log-file /private/tmp/warforge_h104_clean_druid60.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h104_clean_druid60.json --trace-dir=/private/tmp/warforge_h104_clean_druid60_traces --quiet-progress=true
```

Result:

- 9/60 clears, avg final HP `-4.23`, avg rounds `11.07`.
- Flat vs H94/H103 baseline: `REJECT_FLAT_OR_NOISY`.
- R9-R11 focus-active ledger: 81 frames, 28 wins / 53 losses, WR `34.6%`.
- Primary bottlenecks: `debuff_too_small` 30, `debuff_missing` 15,
  `enemy_pressure_spike` 6, `damage_shortfall` 1, `board_mass_shortfall` 1.

New audit command:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h104_clean_druid60_traces --strategy=soft_druid --druid-active-ledger --druid-spore-tree-gap --druid-run-phase --druid-activation-audit --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h94_druid60_traces
```

Spore tree-gap output:

- Spore active in 50 R9-R11 focus frames: 17 wins / 33 losses.
- Average Spore own trees: `0.2`.
- Average total active Druid trees while Spore is active: `26.6`.
- Average other-Druid trees while Spore is active: `26.4`.
- Average own/total ratio: `0.7%`.
- In Spore losses, avg own trees `0.2`, total active trees `24.4`,
  other-Druid trees `24.2`.
- In Spore losses, current debuff avg `15.7%`; diagnostic forest-depth probe
  estimate `21.8%`.
- Zero-own/high-forest Spore loss frames: 21.
- Low-own/high-forest Spore loss frames: 26.
- Low-debuff Spore loss crossings under the diagnostic probe: 21/32.
- Winning low-debuff crossings under the diagnostic probe: 12.
- Spore losses by active forest depth:
  - `0-8`: 1 frame, 0 threshold crossings, debuff `15.0% -> 17.0%`.
  - `9-17`: 6 frames, 0 threshold crossings, debuff `15.0% -> 18.4%`.
  - `18-26`: 15 frames, 11 threshold crossings, debuff `15.4% -> 20.8%`.
  - `27+`: 11 frames, 10 threshold crossings, debuff `16.6% -> 25.4%`.

The new audit emits:

```text
PACKET_CANDIDATE_FOREST_DEPTH_SPORE_SCALING
```

## Interpretation

This is not another Spore base-number nomination. H72 and H75 already tested
that shape and rejected it after weak or flat same-seed outcomes. The new signal
is narrower: Spore often carries almost no own trees while the active Druid
board already has a large forest. A protected forest-depth routing probe could
test whether Spore should read some of the non-Spore active Druid tree depth
instead of relying almost entirely on its own counters.

The old `--druid-path-lag-audit` still emits
`GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`, but that exact no-focus
stabilizer shape was already tested and rejected in H78. Do not chase that stale
gate unless a new packet explains why it is meaningfully different from H78.

The user approved future edits to:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

This slice did not use that approval because the best current evidence points
at Spore runtime/card behavior, not AI focus-slot policy.

## Next Packet Candidate

Prepare a protected gameplay packet for a Druid Spore forest-depth probe. Likely
write surface, pending fresh approval:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`
- `data/cards/druid.yaml` only if the chosen probe needs data/schema changes
- generated `godot/core/data/card_db.gd` only through codegen, never manually

Candidate adoption gates:

- Same-seed Druid 60-run screen must beat H94/H103/H104 by more than local
  ledger optics: clear count, avg final HP, R9-R11 focus-active WR, and active
  loss survivor margins must move together.
- The probe must reduce `debuff_too_small` without merely inflating already
  winning Spore boards.
- It must explain why H72/H75 base debuff buffs failed while forest-depth
  routing targets a different failure mode.
- Full GUT and card-spawn guard before keeping any gameplay change.

## Verification

- PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (22 tests).
- PASS `python3 scripts/analyze_ai_trace.py --help`.
- PASS current-trace analyzer run with `--druid-spore-tree-gap` and H94
  comparison.
- PASS `git diff --check`.
