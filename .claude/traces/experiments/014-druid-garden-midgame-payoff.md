# Episode 014: Druid Garden midgame payoff

## Question

H17 showed that `soft_druid` usually reaches the shop tier needed for Druid
payoffs, but many losses still happen in R8-R10 before Spore/Wrath meaningfully
convert the accumulated Garden setup into combat survival.

Baseline from H17 same-seed observer:

```text
soft_druid: 3/30 wins, avg final HP -2.83, avg rounds 10.23
Lv4 reached 90.0% (avg R7.7), Lv5 reached 63.3% (avg R9.6)
enemy debuffs seen: 26.7%
loss buckets:
  payoff_acquisition_lag: 16/27
  path_lag_hold_pressure: 14/27
  combat_conversion_failure: 7/27
  low_druid_board_ratio: 7/27
  tier_access_lag: 5/27
  payoff_no_debuff_conversion: 4/27
```

## Hypothesis

A narrow Druid card-data change can improve Garden midgame survivability by
moving tree-to-combat conversion earlier, while preserving the intended
small-elite identity and keeping World Tree optional rather than required.

## Constraints

- Change one Druid YAML balance axis at a time.
- Do not edit generated `godot/core/data/card_db.gd` or `card_descs.gd` by hand.
- Preserve Druid identity: no generic unit spam and no mandatory T5 capstone.
- Reject if same-seed observer does not improve the target bucket family or
  creates obvious regression in survivability.

## Review Notes

Multi-review:

- Card design recommended `dr_origin` low-unit growth as the first adoptable
  change because it strengthens the intended `dr_prune -> trees -> dr_origin ->
  all-Druid growth` Garden engine without making Spore/Wrath mandatory.
- Systems review recommended existing numeric YAML fields only, plus codegen,
  focused Druid tests, analyzer guards, same-seed observer, and full GUT before
  closing the slice. It also flagged Druid doc drift around Wrath caps.
- Evidence review supported a reversible card-balance experiment, but warned
  that H17 does not yet prove Spore/Wrath are underpowered. It proposed a
  temporary Spore T2 access probe as the most falsifiable diagnostic, not a
  first adoptable design change.

## Variant A: Origin low-unit Garden growth

Patch:

```text
dr_origin low_unit.pct:
  ★1 0.006 -> 0.008
  ★2 0.009 -> 0.012
  ★3 0.009 -> 0.012
```

Rationale:

- Existing field, existing runtime path, no shop tier/cost/pool disruption.
- Strengthens Garden's board-wide tree-to-combat conversion before World Tree.
- Avoids turning `dr_spore_cloud` into the only viable midgame answer.

Rejection check:

- If same-seed observer does not improve win rate, average final HP, or the
  R8-R10 combat/payoff bucket family, reject or replace with a sharper access
  probe.

Result:

```text
command:
godot --headless --log-file /private/tmp/warforge_h18_origin_variant_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h18_origin_variant_30.json --trace-dir=/private/tmp/warforge_h18_origin_variant_30_traces --quiet-progress=true

baseline: 3/30 wins, avg final HP -2.83, enemy debuffs seen 26.7%
variant:  3/30 wins, avg final HP -3.53, enemy debuffs seen 26.7%

loss bucket deltas:
  payoff_acquisition_lag: 16 -> 15
  payoff_no_debuff_conversion: 4 -> 5
  path_lag_hold_pressure: 14 -> 14
  combat_conversion_failure: 7 -> 7
  low_druid_board_ratio: 7 -> 6
  tier_access_lag: 5 -> 5
```

Verdict: REJECT. The variant did not improve win rate or debuff visibility and
regressed average final HP. Reverted the YAML/test change before the next
probe.

## Variant B: Temporary Spore access probe

Patch for diagnosis only:

```text
dr_spore_cloud tier: 3 -> 2
```

Purpose:

- Test whether earlier/cheaper Spore access sharply improves payoff acquisition,
  debuff visibility, and R8-R10 survival.
- Do not treat T2 Spore as an adoptable final design without a separate review;
  this changes shop odds, cost, and global tier-pool composition.

Result:

```text
command:
godot --headless --log-file /private/tmp/warforge_h18_spore_t2_probe_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h18_spore_t2_probe_30.json --trace-dir=/private/tmp/warforge_h18_spore_t2_probe_30_traces --quiet-progress=true

baseline: 3/30 wins, avg final HP -2.83, enemy debuffs seen 26.7%
variant:  2/30 wins, avg final HP -4.30, enemy debuffs seen 50.0%

loss bucket deltas:
  payoff_acquisition_lag: 16 -> 8
  payoff_activation_lag: 0 -> 5
  combat_conversion_failure: 7 -> 12
  path_lag_hold_pressure: 14 -> 12
  low_druid_board_ratio: 7 -> 9
  tier_access_lag: 5 -> 6
```

Verdict: REJECT. Earlier Spore access did what the diagnostic expected for
payoff acquisition/debuff visibility, but it worsened clears and moved failures
into combat conversion/activation. This argues against a tier/cost access fix as
the first adoptable change.

## Variant C: Spore ★1 conversion strength

Patch:

```text
dr_spore_cloud ★1 AS debuff:
  base_pct 0.15 -> 0.20
  tree_scale_pct 0.015 -> 0.02
```

Rationale:

- Keeps Spore at T3, preserving shop tier/cost/pool shape.
- Uses the existing non-stacking `debuff_store` path, so duplicate Spore is not
  mandatory.
- Tests whether Druid fails because its midgame payoff is too weak when found,
  rather than too inaccessible.

Result:

```text
command:
godot --headless --log-file /private/tmp/warforge_h18_spore_strength_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h18_spore_strength_30.json --trace-dir=/private/tmp/warforge_h18_spore_strength_30_traces --quiet-progress=true

baseline: 3/30 wins, avg final HP -2.83, enemy debuffs seen 26.7%, AS avg max 4.4%
variant:  3/30 wins, avg final HP -2.77, enemy debuffs seen 26.7%, AS avg max 5.6%

loss buckets: unchanged from baseline.
```

Verdict: WEAK/INCONCLUSIVE. The AS-only strength bump was directionally better
than rejected variants, but too small to move the loss buckets or clear rate.

## Variant D: Spore ★1 dual debuff

Patch:

```text
dr_spore_cloud ★1:
  AS  base_pct 0.20, tree_scale_pct 0.020, cap 0.50
  ATK base_pct 0.12, tree_scale_pct 0.012, cap 0.35
```

Rationale:

- H18-B proved earlier Spore access raises debuff visibility but does not solve
  combat conversion by itself.
- H18-C proved stronger AS alone barely moves the paired trace.
- Adding a smaller ATK debuff at ★1 tests whether Spore needs to reduce enemy
  damage as well as attack frequency when it is the R7-R8 payoff.

Result:

```text
command:
godot --headless --log-file /private/tmp/warforge_h18_spore_dual_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h18_spore_dual_30.json --trace-dir=/private/tmp/warforge_h18_spore_dual_30_traces --quiet-progress=true

baseline: 3/30 wins, avg final HP -2.83, enemy debuffs seen 26.7%
variant:  3/30 wins, avg final HP -4.00, enemy debuffs seen 26.7%

loss buckets: effectively unchanged; ATK avg max rose to 4.0%, but average HP
regressed and path-lag skips rose slightly.
```

Verdict: REJECT. Stronger Spore combat stats do not address enough losing runs
because the dominant acquisition/timing buckets remain unchanged.

## Variant E: Lifebeat shield curve

Patch:

```text
dr_lifebeat tree_shield:
  ★1 base_pct 0.05 -> 0.06, tree_scale_pct 0.030 -> 0.035
  ★2 base_pct 0.08 -> 0.09, tree_scale_pct 0.040 -> 0.045
  ★3 base_pct 0.08 -> 0.09, tree_scale_pct 0.050 -> 0.055
```

Rationale:

- H18-A/D showed payoff-specific changes did not move the dominant losing-run
  shape enough.
- `dr_lifebeat` is an existing R1 survivability card frequently bought/merged
  by the AI, and its shield naturally scales with the same tree setup Druid is
  already building.
- This keeps shop access and payoff identities intact while improving R7-R10
  survival pressure.

Result:

```text
command:
godot --headless --log-file /private/tmp/warforge_h18_lifebeat_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h18_lifebeat_30.json --trace-dir=/private/tmp/warforge_h18_lifebeat_30_traces --quiet-progress=true

baseline: 3/30 wins, avg final HP -2.83
variant:  3/30 wins, avg final HP -2.87

loss bucket deltas:
  payoff_acquisition_lag: 16 -> 16
  path_lag_hold_pressure: 14 -> 15
  combat_conversion_failure: 7 -> 7
  low_druid_board_ratio: 7 -> 7
  tier_access_lag: 5 -> 5
```

Verdict: REJECT. The shield curve was safe but did not improve the paired
outcome or buckets.

## H18 Conclusion

No Druid card-number variant earned adoption in this slice.

Learnings:

- A direct Garden engine buff (`dr_origin`) did not help.
- Earlier Spore access improved acquisition/debuff visibility but worsened
  outcomes, so tier/cost access is not the first answer.
- Stronger Spore combat conversion and stronger Lifebeat defense were flat or
  worse in the paired 30-run gate.
- The current all-Druid loss buckets are too path-mixed to support confident
  card tuning.

Next allowed action:

- Improve analyzer observability by stratifying Druid losses by detected path
  (`druid_garden`, `druid_world_tree`, undetected), then run the preserved H17
  baseline and use that split to pick the next change.

## H18 Adopted Observability Patch

The retained H18 change is an analyzer improvement, not a card-data change.
`summarize_druid_loss_buckets()` now reports a `by_path` split keyed by detected
Druid route while preserving the aggregate bucket summary.

Preserved H17 same-seed split after the patch:

```text
by detected path:
  druid_garden: runs 8, losses 8, wins 0, buckets {'payoff_acquisition_lag': 6, 'owned_not_active_gap': 1, 'payoff_no_debuff_conversion': 1, 'path_lag_hold_pressure': 2, 'tier_access_lag': 3, 'low_druid_board_ratio': 2, 'combat_conversion_failure': 1}, payoff funnel offered/affordable/bought 4/2/2
  druid_world_tree: runs 18, losses 15, wins 3, buckets {'payoff_acquisition_lag': 7, 'path_lag_hold_pressure': 9, 'low_druid_board_ratio': 1, 'combat_conversion_failure': 5, 'payoff_no_debuff_conversion': 3, 'tier_access_lag': 1}, payoff funnel offered/affordable/bought 11/9/8
  undetected: runs 4, losses 4, wins 0, buckets {'tier_access_lag': 1, 'payoff_acquisition_lag': 3, 'low_druid_board_ratio': 4, 'path_lag_hold_pressure': 3, 'combat_conversion_failure': 1}, payoff funnel offered/affordable/bought 2/1/1
```

H18 final decision:

- Reject card-number buffs for now. Five variants either regressed or failed to
  move the measured failure bucket.
- Move to H19 with a narrower AI-policy question: can soft-Druid scoring and
  protected-card behavior support the detected Garden path without smuggling in
  World Tree as the default answer?
