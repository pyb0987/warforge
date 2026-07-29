# Episode 017: Steampunk local tier-access probe

## Context

H20 added Steampunk loss buckets and showed a clean access signal in the current
20-run slice:

```text
soft_steampunk baseline: 5/20 wins, avg HP 2.15
Lv4 reached 20%, Lv5 reached 5%
loss buckets: tier_access_lag 15/15, payoff_acquisition_lag 14/15
loss payoff funnel: offered/affordable/bought 1/1/1
```

## H21-A: Reuse Path-tier-access Override

Hypothesis:

- Steampunk is dying because slow-roll blocks scheduled Lv4/Lv5 access.
- Reusing the existing Druid path-tier-access override for Steampunk should
  raise Lv4/Lv5 access and improve payoff acquisition.

Patch:

```gdscript
func _should_force_path_tier_access(...):
    if strategy != "soft_druid" and strategy != "soft_steampunk":
        return false
```

Direct test:

```text
PASS test_ai_agent.gd 39/39
```

Same-seed 140-run observer:

```bash
godot --headless --log-file /private/tmp/warforge_h21_steampunk_tier_access_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h21_steampunk_tier_access_140.json --trace-dir=/private/tmp/warforge_h21_steampunk_tier_access_140_traces --quiet-progress=true
```

Result:

```text
overall: 61/140 wins, avg HP 6.49 (baseline 64/140, avg HP 7.84)
soft_steampunk: 2/20 wins, avg HP -7.3 (baseline 5/20, avg HP 2.15)
soft_steampunk Lv4 reached 90%, Lv5 reached 55%
soft_steampunk buys/run 28.8 (baseline 45.2)
soft_steampunk rerolls/run 6.9 (baseline 15.1)
loss buckets: affordability_pressure 18/18, payoff_acquisition_lag 13/18,
  low_steampunk_board_ratio 9/18
```

Decision:

- Reject and revert. The patch proved that raw level access is not sufficient;
  it spends too much deck-building economy too early and worsens survival.
- Post-revert focused check: PASS `test_ai_agent.gd` 37/37.

Next:

- Look for a smaller Steampunk fix that reduces branch mixing or improves
  payoff targeting without forcing early levels.
