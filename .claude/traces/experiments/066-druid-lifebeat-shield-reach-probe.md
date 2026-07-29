# Experiment 066 — Druid Lifebeat Shield Reach Probe

Date: 2026-07-29
Status: REJECTED / ROLLED BACK

## Question

After H69 closed the remaining Druid runtime/data parity gaps, `soft_druid` still
lost most R9-R11 focus-active battles with no allied survivors. Would changing
`dr_lifebeat` star 1/2 `tree_shield.target` from adjacent reach to `all_druid`
improve Druid combat conversion enough to adopt?

## Review Input

Used multi-review before editing because this is a balance-affecting card data
decision.

- Design/balance view: Lifebeat all-Druid shielding is the narrowest thematic
  survivability probe. It supports Druid boards and avoids leaking shield value
  to adjacent non-Druid mercenaries.
- Measurement view: same-seed improvement is not enough by itself. Adoption
  should improve clears, average HP, and focus-active battle conversion together,
  preserve focus-active sample size, and then reproduce direction on a disjoint
  seed.
- Implementation/risk view: keep the probe YAML-only plus generated data/tests;
  avoid new runtime timing or combat-engine behavior.

## Baseline

Command:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h70_baseline godot --headless --log-file /private/tmp/warforge_h70_baseline_druid_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h70_baseline_druid_30.json --trace-dir=/private/tmp/warforge_h70_baseline_druid_30_traces --quiet-progress=true
```

Results:

- Clears: 4/30.
- Average final HP: -4.17.
- Average rounds reached: 11.07.
- Focus-active battles: 62 total, 27 won / 35 lost, 43.5% WR.
- Active loss survivors: 0.0 allies, 15.9 enemies.
- Loss buckets: `path_lag_hold_pressure` 16/26 losses, `combat_conversion_failure` 10/26.

## Variant

Temporary change:

- `data/cards/druid.yaml`: `dr_lifebeat` star 1/2 `tree_shield.target`
  `self_and_both_adj` -> `all_druid`.
- Generated card data refreshed.
- Probe-only test added for all-Druid shield reach and non-Druid exclusion.

Command:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h70_lifebeat_probe godot --headless --log-file /private/tmp/warforge_h70_lifebeat_probe_druid_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h70_lifebeat_probe_druid_30.json --trace-dir=/private/tmp/warforge_h70_lifebeat_probe_druid_30_traces --quiet-progress=true
```

Results:

- Clears: 5/30.
- Average final HP: -2.83.
- Average rounds reached: 11.40.
- Focus-active battles: 75 total, 34 won / 41 lost, 45.3% WR.
- Active loss survivors: 0.0 allies, 14.7 enemies.
- Loss buckets: `path_lag_hold_pressure` 18/25 losses, `combat_conversion_failure` 12/25.

## Decision

Rejected and rolled back.

The probe moved some surface metrics in the right direction, but not enough to
adopt:

- Clears improved only 4/30 -> 5/30, below the pre-review adoption threshold.
- Active losses still ended with 0.0 allied survivors.
- Enemy survivors in active losses remained high at 14.7, above the target
  ceiling.
- The central loss buckets remained path pressure plus combat conversion rather
  than showing a clear survivability break.
- Because the same-seed result was weak and the user asked to pause after this
  run, no disjoint-seed confirmation was started.

## Post-Rollback Verification

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q` (3 tests).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_druid_system.gd -glog=1 -gexit` (53/53).
- PASS `python3 scripts/lint_card_spawn.py`.

## Resume Note

Do not retry Lifebeat star 1/2 all-Druid shield reach as-is. The next Druid
probe should target R9-R11 active-battle conversion more directly, likely
through payoff battle math, enemy pressure interaction, or a better way to leave
some allied survivors in failed focus-active battles.
