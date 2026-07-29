# Episode 015: Druid path-aware AI follow-up

## Context

H18 rejected five Druid card-number/access variants and added path-stratified
loss buckets. The preserved same-seed H17 split showed Garden as the weakest
route:

```text
druid_garden: runs 8, losses 8, wins 0, payoff_acquisition_lag 6, payoff funnel 4/2/2
druid_world_tree: runs 18, losses 15, wins 3, payoff_acquisition_lag 7, payoff funnel 11/9/8
undetected: runs 4, losses 4, wins 0, payoff_acquisition_lag 3, payoff funnel 2/1/1
```

## Multi-review Synthesis

Three read-only critics agreed that the next plausible probe was AI policy, not
another card-number buff.

- Do not change path detection unless evidence shows the analyzer is wrong.
- First remove World Tree-exclusive infrastructure from global Druid
  `core_cards`, because the old `core +12` cancelled the Garden anti-path
  penalty on `dr_deep`/`dr_wt_root`.
- Avoid using `capstone_cards` as a generic payoff list; it also influences
  late-power and path-lag purchase exceptions.

## H19-A: Shared-Payoff Core Config

Patch:

```gdscript
"core_cards": ["dr_grace", "dr_spore_cloud", "dr_wrath"],
"capstone_cards": ["dr_wrath", "dr_world"],
```

Direct tests:

```text
PASS test_ai_agent.gd 37/37
PASS test_ai_build_path.gd 36/36
PASS test_ai_theme_scorer.gd 11/11
PASS test_ai_board_eval.gd 16/16
PASS scripts.tests.test_analyze_ai_trace 8/8
PASS scripts/codegen_card_db.py --check
PASS git diff --check
PASS full GUT 1208/1208
```

Same-seed 30-run observer:

```bash
godot --headless --log-file /private/tmp/warforge_h19_druid_core_shared_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h19_druid_core_shared_30.json --trace-dir=/private/tmp/warforge_h19_druid_core_shared_30_traces --quiet-progress=true
```

Result:

```text
soft_druid: 3/30 wins, avg final HP -2.80, avg rounds 10.23
aggregate buckets: payoff_acquisition_lag 15, path_lag_hold_pressure 14, combat_conversion_failure 8
by detected path:
  druid_garden: runs 8, losses 8, wins 0, buckets {'payoff_acquisition_lag': 6, 'owned_not_active_gap': 1, 'payoff_no_debuff_conversion': 1, 'path_lag_hold_pressure': 2, 'tier_access_lag': 3, 'low_druid_board_ratio': 2, 'combat_conversion_failure': 1}, payoff funnel 4/2/2
  druid_world_tree: runs 18, losses 15, wins 3, buckets {'payoff_acquisition_lag': 6, 'path_lag_hold_pressure': 9, 'low_druid_board_ratio': 1, 'combat_conversion_failure': 6, 'payoff_no_debuff_conversion': 3, 'tier_access_lag': 1}, payoff funnel 11/9/9
  undetected: runs 4, losses 4, wins 0, buckets {'tier_access_lag': 1, 'payoff_acquisition_lag': 3, 'low_druid_board_ratio': 4, 'path_lag_hold_pressure': 3, 'combat_conversion_failure': 1}, payoff funnel 2/1/1
```

Decision: adopt as a small design cleanup only. It removes the global
World-Tree-core score leak and has no paired 30-run aggregate regression, but it
does not solve Garden.

## H19-B: Path-lag Anti/Capstone Blocking Probe

Patch: after path focus, block detected anti-cards from the global critical
exception and block off-path global capstones during Druid payoff lag.

Direct test:

```text
PASS test_ai_agent.gd 40/40
```

Same-seed 30-run observer:

```bash
godot --headless --log-file /private/tmp/warforge_h19b_druid_pathaware_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072617 --out=/private/tmp/warforge_h19b_druid_pathaware_30.json --trace-dir=/private/tmp/warforge_h19b_druid_pathaware_30_traces --quiet-progress=true
```

Result:

```text
soft_druid: 3/30 wins, avg final HP -3.40, avg rounds 10.20
aggregate buckets: payoff_acquisition_lag 14, path_lag_hold_pressure 16, combat_conversion_failure 10
by detected path:
  druid_garden: runs 16, losses 14, wins 2, payoff funnel 9/7/7
  druid_world_tree: runs 10, losses 9, wins 1, payoff funnel 5/4/4
  undetected: runs 4, losses 4, wins 0, payoff funnel 3/2/2
```

Decision: reject and revert. It improves Garden classification and payoff buys
but worsens average HP, raises path-lag holds, and does not improve total wins.

## Conclusion

H19 keeps only the shared-payoff Druid core config. The next Druid work should
not add more path-lag blocking. The remaining issue looks more like a broader
combat/economy conversion problem: even when Garden acquires payoff cards, the
run does not reliably convert those cards into enough combat survival.
