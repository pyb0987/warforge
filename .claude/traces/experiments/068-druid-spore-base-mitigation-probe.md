# Experiment 068 — Druid Spore Base Mitigation Probe

Date: 2026-07-29
Status: DONE - gameplay probe rejected and rolled back

## Question

After H71 showed that R9-R11 Druid focus-active losses were dominated by
`debuff_too_small`, would a narrow Spore Cloud base mitigation increase improve
the Druid completion floor enough to adopt?

## Review Synthesis

Used multi-review because this was a card balance decision.

- Design critic: target Spore Cloud base values only. H71 pointed at low-tree
  star 1 Spore, so scaling, cap increases, and new Spore/Wrath pairing mechanics
  would be the wrong first lever.
- Measurement critic: use the H71 60-run baseline for comparison, require a
  60-run same-seed candidate before adoption, and confirm on a disjoint seed
  only if same-seed gates pass.
- Implementation critic: keep the probe YAML-only, regenerate generated card
  data, update exact-value tests, and do not touch Druid runtime, AI, analyzer,
  star 3, or caps.

Local trace check before editing confirmed the H71 signal:

- R9-R11 Spore-present frames: 50.
- Spore-present losses: 33.
- All Spore-present losses had star 1 Spore.
- Star 1 Spore-present losses averaged 0.24 trees; 28/33 had 0 trees.

Decision: run one star 1/2 Spore base-value probe.

## Temporary Candidate

Changed only `data/cards/druid.yaml` and regenerated `card_db.gd` /
`card_descs.gd`:

- `dr_spore_cloud` star 1 AS base: `0.15 -> 0.20`.
- `dr_spore_cloud` star 2 AS base: `0.20 -> 0.25`.
- `dr_spore_cloud` star 2 ATK base: `0.20 -> 0.25`.
- Tree scaling, caps, star 3, runtime, and AI unchanged.

## Pre-Probe Verification

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `python3 -m unittest scripts.tests.test_card_desc_codegen scripts.tests.test_lint_card_spawn -q` (13 tests).
- PASS `test_druid_system.gd` 53/53.
- PASS `test_chain_engine.gd` 21/21.

## 60-Run Candidate Evidence

Command:

```bash
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h72_spore60 godot --headless --log-file /private/tmp/warforge_h72_spore60.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h72_spore60.json --trace-dir=/private/tmp/warforge_h72_spore60_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h72_spore60_traces --strategy=soft_druid --druid-active-ledger
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h72_spore60_traces --strategy=soft_druid --druid-battle-conversion
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h72_spore60_traces --strategy=soft_druid --druid-loss-buckets
python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h72_spore60.json --out /private/tmp/warforge_h72_spore60_summary.md
```

Compared with the H71 60-run baseline (`9/60` clears, avg HP `-4.23`,
R9-R11 focus-active `28/53`):

- Clears: `10/60`, up only +1 run and below the `14/60` adoption gate.
- Average final HP: `-3.65`, a modest +0.58 improvement.
- Average rounds reached: `11.18`, nearly flat.
- R9-R11 focus-active ledger: 83 frames, 33 wins / 50 losses, 39.8% WR.
- Full focus-active battle conversion: 137 battles, 67 wins / 70 losses,
  48.9% WR.
- Spore-active battle conversion across all rounds: 75 battles, 42 wins /
  33 losses, 56.0% WR.
- Active loss survivors stayed flat: 0.0 allied survivors / 14.2 enemy
  survivors.

Ledger bottlenecks shifted:

- `damage_shortfall`: 19.
- `debuff_missing`: 16.
- `mixed_margin`: 6.
- `enemy_pressure_spike`: 5.
- `near_miss_survivability`: 2.
- `tree_depth_shortfall`: 1.
- `board_mass_shortfall`: 1.

Spore-present R9-R11 groups improved but still did not solve the run:

- `dr_spore_cloud`: 32 frames, 16 wins / 16 losses, 50.0% WR, loss enemy
  survivors 13.9, average debuff 20.8%.
- `dr_spore_cloud+dr_wrath`: 13 frames, 6 wins / 7 losses, 46.2% WR, loss
  enemy survivors 13.6, average debuff 20.9%.

## Decision

Reject and roll back the candidate.

The probe successfully removed `debuff_too_small` as the dominant ledger label
and improved Spore-active conversion, but it failed the adoption gates that
matter for game completion:

- clears remained far below the `14/60` threshold.
- R9-R11 focus-active WR stayed below 50%.
- active losses still left no allied survivors.
- enemy survivors in active losses stayed around 14, not <=10.

Because same-seed evidence failed, no disjoint-seed confirmation or all-strategy
smoke was run.

## Post-Rollback Verification

The temporary Spore values were restored and generated data was regenerated.

- PASS `python3 scripts/codegen_card_db.py --check`.
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `test_druid_system.gd` 53/53.
- PASS `test_chain_engine.gd` 21/21.
- PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_chain_engine.gd godot/tests/test_druid_system.gd`.

## Resume Note

Do not keep pushing Spore base mitigation. H72 showed that Spore can reach a
healthier conversion rate without moving the Druid run floor enough.

Recommended H73: inspect or probe Druid offensive battle math, especially
Wrath/World Tree conversion in R9-R11 focus-active losses. The new dominant
shape is `damage_shortfall`, not `debuff_too_small`.
