# Experiment 071 — Druid Spore + Wrath Coupled Probe

Date: 2026-07-29
Status: DONE - gameplay probe rejected and rolled back; Spore star 2 exact test kept

## Question

H72 showed that a Spore-only base mitigation buff improved local conversion but
failed run-level gates. H73 showed that a Wrath-only base offense buff was flat.
Would combining those exact two rejected deltas reveal a real coupled
Spore+Wrath interaction for the Druid R9-R11 floor?

## Review Synthesis

Used multi-review because this was a balance decision. The reviewer agents
returned slowly, so the reversible YAML-only probe started after the pre-probe
checks, then the returned reviews were folded into the decision.

- Design critic: run the coupled probe only as an interaction falsification
  test. Use the exact H72 and H73 values together; do not touch World Tree,
  star 3, caps, tree scaling, AI, economy, runtime, or difficulty.
- Measurement critic: same-seed evidence is only a screen. Require at least
  `12/60` clears, average HP around `-3.30` or better, R9-R11 focus WR above
  H71 by at least about `8pp`, and survivor/bottleneck movement before any
  disjoint-seed confirmation.
- Implementation critic: YAML-only is safe if generated files are produced only
  through codegen and exact-value tests are synchronized temporarily. Roll back
  only the probe values on reject because the worktree already contains
  legitimate pre-existing changes.

One measurement bullet said active-loss enemy survivors should be `>= 14.0`,
which contradicts the stated false-green risk and the H74 survivor-margin
invariant. I treated survivor improvement as requiring enemy survivors to go
down, not remain high.

## Candidate

Temporarily changed `data/cards/druid.yaml` and regenerated generated data:

- `dr_spore_cloud` star 1 AS `base_pct`: `0.15 -> 0.20`.
- `dr_spore_cloud` star 2 AS/ATK `base_pct`: `0.20 -> 0.25`.
- `dr_wrath` star 1 `atk_base_pct`: `0.80 -> 1.20`.
- `dr_wrath` star 2 `atk_base_pct`: `1.20 -> 1.60`.

Unchanged:

- Spore tree scaling, caps, and star 3.
- Wrath tree scaling, HP, unit caps, and star 3.
- World Tree, runtime, combat engine, AI, difficulty, UI, and protected
  `godot/sim/**`.

## Pre-Probe Verification

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q` (3 tests).
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `test_druid_system.gd` 53/53 before candidate edits.

Candidate-local verification after YAML/codegen:

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q` (3 tests).
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `test_druid_system.gd` 54/54.

## 60-Run Candidate Evidence

Command:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h75_coupled60 godot --headless --log-file /private/tmp/warforge_h75_coupled60.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h75_coupled60.json --trace-dir=/private/tmp/warforge_h75_coupled60_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-active-ledger --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-battle-conversion
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-loss-buckets
python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h75_coupled60.json --out /private/tmp/warforge_h75_coupled60_summary.md
```

Compared with H71 baseline:

- Clears: `9/60 -> 10/60` (`+1`), below the screen gate.
- Average final HP: `-4.23 -> -3.45` (`+0.78`), below the screen gate.
- Average rounds: `11.07 -> 11.20` (`+0.13`).
- R9-R11 focus ledger: `81 -> 83` frames, `34.6% -> 41.0%` WR (`+6.4pp`),
  below the screen gate.
- Active-loss survivors: ally `0.0 -> 0.0`, enemy `13.8 -> 13.8`.
- Bottleneck deltas: `debuff_too_small -30`, `debuff_missing 0`,
  `damage_shortfall +18`, `mixed_margin +7`.
- H74 screen verdict: `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`.

Focus-combo deltas:

- `dr_spore_cloud`: WR `+12.5pp`, but loss enemy survivors worsened
  `+0.8`.
- `dr_spore_cloud+dr_wrath`: WR `+0.0pp`, loss enemy survivors improved only
  `-0.1`.
- `dr_wrath`: WR `+7.8pp`, but loss enemy survivors worsened `+1.2`.

Full focus-active battle conversion:

- `138` focus-active battles, `68` won / `70` lost, WR `49.3%`.
- Active losses still had ally `0.0`, enemy `14.0`.
- Spore card battles reached `54.7%` WR, but Wrath card battles stayed `42.0%`
  and Spore+Wrath R9-R11 frames did not improve.

Loss buckets:

- `50/60` losses.
- `combat_conversion_failure` 17.
- `path_lag_hold_pressure` 26.
- `payoff_acquisition_lag` 18.
- `payoff_no_debuff_conversion` 11.

## Decision

Reject and roll back the coupled gameplay values.

The candidate failed the H75 gates:

- Same-seed clear gain was only `+1`.
- Average HP improved by less than `+1`.
- R9-R11 focus WR improved by less than the planned `+8pp`.
- Active-loss ally survivors stayed `0.0`.
- Active-loss enemy survivors did not improve.
- The H74 comparison reported `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`.
- The intended coupled Spore+Wrath frames had no win-rate lift.

No disjoint-seed confirmation or broad smoke was run because the same-seed
screen failed.

## Retained Change

Kept a non-gameplay test hardening improvement:

- `test_spore_cloud_s2_sets_enemy_as_and_atk_debuff` now asserts adopted star 2
  Spore AS/ATK debuff math exactly: `0.20 + trees*0.02`.

This complements the H73 retained exact Wrath tests and reduces future
card-data/runtime drift risk.

## Post-Rollback Verification

The temporary gameplay values were restored and generated data was regenerated.

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen scripts.tests.test_lint_card_spawn -q` (13 tests).
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `test_druid_system.gd` 54/54.
- PASS `test_chain_engine.gd` 21/21.
- PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_druid_system.gd`.

## Resume Note

Do not keep pushing Spore/Wrath base-number probes. H72, H73, and H75 together
show that base mitigation/offense can relabel the R9-R11 failures but does not
create allied survivors or enough terminal clear-rate movement.

Recommended H76: pivot away from Spore/Wrath base values. Inspect Druid
path-lag/payoff acquisition and board-state conversion, especially why
Spore+Wrath frames are present but not winning, or broaden to a survival-curve
diagnostic across Druid run phases before touching more card numbers.
