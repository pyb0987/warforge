# Experiment 069 — Druid Wrath Base Offense Probe

Date: 2026-07-29
Status: DONE - gameplay probe rejected and rolled back; exact Wrath tests kept

## Question

After H72 showed that a Spore Cloud base mitigation buff improved local
Spore-present conversion but failed run-level gates, would a narrow Wrath
base-damage increase solve the R9-R11 Druid offensive conversion gap?

## Review Synthesis

Used multi-review because this was another card balance decision.

- Design critic: test Wrath base ATK only. H72 made `damage_shortfall` visible,
  Wrath is the T4 combat payoff, and most failed Wrath frames were star 1 with
  zero trees.
- Measurement critic: compare against the accepted H71 60-run baseline, not the
  rejected H72 candidate. Require 60 same-seed runs before adoption.
- Implementation critic: use a YAML-only star 1/2 ATK probe, leave World Tree,
  Spore, HP, caps, star 3, runtime, AI, and analyzer unchanged. Convert vague
  Wrath `assert_gt` tests into exact-value assertions.

## Candidate

Temporarily changed `data/cards/druid.yaml` and regenerated generated data:

- `dr_wrath` star 1 `atk_base_pct`: `0.8 -> 1.2`.
- `dr_wrath` star 2 `atk_base_pct`: `1.2 -> 1.6`.
- `atk_tree_pct`, `hp_pct`, `unit_cap`, star 3, World Tree, Spore Cloud,
  runtime, and AI unchanged.

## Pre-Probe Verification

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q` (3 tests).
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `test_druid_system.gd` 53/53.
- PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_druid_system.gd`.

## 60-Run Candidate Evidence

Command:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h73_wrath60 godot --headless --log-file /private/tmp/warforge_h73_wrath60.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h73_wrath60.json --trace-dir=/private/tmp/warforge_h73_wrath60_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h73_wrath60_traces --strategy=soft_druid --druid-active-ledger
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h73_wrath60_traces --strategy=soft_druid --druid-battle-conversion
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h73_wrath60_traces --strategy=soft_druid --druid-loss-buckets
python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h73_wrath60.json --out /private/tmp/warforge_h73_wrath60_summary.md
```

Compared with the accepted H71 60-run baseline (`9/60` clears, avg HP `-4.23`,
R9-R11 focus-active `28/53`):

- Clears: `9/60`, no improvement.
- Average final HP: `-3.80`, a modest +0.43 movement.
- Average rounds reached: `11.08`, flat.
- R9-R11 focus-active ledger: 81 frames, 30 wins / 51 losses, 37.0% WR.
- Full focus-active battle conversion: 131 battles, 60 wins / 71 losses,
  45.8% WR.
- Active loss survivors: 0.0 allied survivors / 14.2 enemy survivors.
- Loss buckets: `combat_conversion_failure` 19, `path_lag_hold_pressure` 27,
  `payoff_acquisition_lag` 18, `payoff_no_debuff_conversion` 11.

R9-R11 ledger bottlenecks:

- `debuff_too_small`: 30.
- `debuff_missing`: 14.
- `enemy_pressure_spike`: 5.
- `damage_shortfall`: 1.
- `board_mass_shortfall`: 1.

## Decision

Reject and roll back the Wrath base buff.

The candidate failed the H73 gates:

- clears stayed at `9/60`.
- R9-R11 focus-active WR stayed well below 50%.
- active losses still left no allied survivors.
- active-loss enemy survivors stayed around 14.
- the target bottleneck did not become a run-floor improvement.

No disjoint-seed confirmation or cross-lane smoke was run because the same-seed
candidate failed.

## Retained Change

Kept a non-gameplay test hardening improvement in `test_druid_system.gd`:

- `test_wrath_persistent_buffs_when_few_units` now asserts exact adopted star 1
  Wrath ATK math: `0.80 + trees*0.05`.
- `test_wrath_s2_higher_buff` now asserts exact adopted star 2 Wrath ATK and
  HP math: `1.20 + trees*0.08`, HP +60%.

This preserves the implementation critic's useful finding that vague `assert_gt`
coverage could hide wrong Wrath math.

## Post-Rollback Verification

The temporary Wrath values were restored and generated data was regenerated.

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q` (3 tests).
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `test_druid_system.gd` 53/53.
- PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_druid_system.gd`.

## Resume Note

Do not continue isolated Wrath base buffs. H72 and H73 together suggest Druid's
R9-R11 floor is coupled: Spore-alone exposes damage shortfall; Wrath-alone
falls back to insufficient Spore mitigation and no survivor-margin movement.

Recommended H74: either add a small battle contribution ledger that records
pre-combat per-card ATK/HP/AS/units for focus cards, or explicitly test a
combined Spore+Wrath probe as a coupled hypothesis rather than another
single-card number tweak.
