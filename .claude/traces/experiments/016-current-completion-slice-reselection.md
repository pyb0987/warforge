# Episode 016: Current completion slice reselection

## Context

H17-H19 focused on Druid. That work improved observability and removed a small
Druid AI scoring leak, but repeated Druid-local card and policy probes did not
produce a convincing win-rate or HP improvement.

H20 re-measures the current full self-play surface before picking the next
completion-oriented slice.

## Current Observer Snapshot

Command:

```bash
godot --headless --log-file /private/tmp/warforge_h20_current_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h20_current_140.json --trace-dir=/private/tmp/warforge_h20_current_140_traces --quiet-progress=true
```

Result:

```text
overall: 64/140 wins, 45.7% clear rate, avg final HP 7.84, no observer alerts
aggressive: 15/20 wins, avg HP 16.6
adaptive: 13/20 wins, avg HP 16.3
economy: 11/20 wins, avg HP 10.8
soft_military: 9/20 wins, avg HP 6.9
soft_predator: 9/20 wins, avg HP 4.4
soft_steampunk: 5/20 wins, avg HP 2.15
soft_druid: 2/20 wins, avg HP -2.3
```

Analyzer highlights:

```text
soft_druid:
  Lv4 reached 90.0% avg R7.7; Lv5 reached 60.0% avg R9.6
  theme mix 62.5%; paths world_tree 11, garden 6
  loss buckets: payoff_acquisition_lag 10, path_lag_hold_pressure 10,
    low_druid_board_ratio 7, combat_conversion_failure 5
  Garden: 0/6, payoff funnel 4/2/2

soft_steampunk:
  Lv4 reached 20.0% avg R11.0; Lv5 reached 5.0% avg R13.0
  theme mix 87.5%; paths focus 12, spread 8
  final current-phase progress focus 10%, spread 20%
  top purchases remain mostly T1/T2 Steampunk and neutral glue
```

## Pending Multi-review

The next target selection is under read-only multi-review:

- Evidence critic: choose Druid vs Steampunk vs general-system target from
  causal confidence and measurable gate.
- Design critic: choose from player-impact/game-feel, including whether live UX
  issues outrank self-play balance.
- Systems critic: choose the smallest reversible target with reliable tests.

## Multi-review Result

The critics converged on Steampunk rather than another Druid probe:

- Evidence critic: choose Steampunk because the causal shape is cleaner than
  Druid after H17-H19; target late-tier access.
- Design critic: choose Steampunk payoff access as a player-facing promise
  issue, not pure win-rate tuning.
- Systems critic: make the first Steampunk slice instrumentation-only; add
  loss buckets before a gameplay probe.

## H20 Implementation

Added `--steampunk-loss-buckets` to `scripts/analyze_ai_trace.py`.

Focused verification:

```text
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace
```

Current H20 trace after adding the buckets:

```text
soft_steampunk losses: 15/20
bucket counts:
  tier_access_lag: 15
  payoff_acquisition_lag: 14
  affordability_pressure: 15
  threshold_pressure: 15
  no_space_pressure: 10
  current_phase_lag: 10
  branch_mix: 10
  capstone_access_lag: 3
  payoff_activation_gap: 1
  owned_not_active_gap: 2
first shop level 4 in losses: {None: 13, 10: 2}
first shop level 5 in losses: {None: 15}
loss payoff funnel: offered/affordable/bought 1/1/1
by detected path:
  steampunk_focus: 12 runs, 9 losses, 3 wins, payoff funnel 0/0/0
  steampunk_spread: 8 runs, 6 losses, 2 wins, payoff funnel 1/1/1
```

Conclusion:

- H20 is complete as an observability slice.
- H21 should test one Steampunk-local level-access behavior change. The first
  candidate is to let Steampunk use the existing path-tier-access override that
  Druid already uses, instead of introducing a new global economy knob.
