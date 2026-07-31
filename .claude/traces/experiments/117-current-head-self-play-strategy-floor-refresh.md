# 117 - Current-Head Self-Play Strategy-Floor Refresh

Date: 2026-07-31
Status: DONE - no-edit readiness evidence

## Purpose

After H118 and H119, refresh M1 strategy-floor evidence from current clean
`main` using the all-core D1 self-play observer.

This run checks whether the user-approved AI maintenance changed the completion
picture enough to pick a new next slice. It does not implement H105 and does not
edit gameplay files.

## Source State

- Branch: `main`
- HEAD before scout: `932bb8b Refresh H105 preflight after AI guard`
- Observer metadata:

```text
commit 932bb8b8d6f87c5b253e4760fece837d28cdaa22
dirty false
status_short []
```

## Commands

Self-play observer:

```text
godot --headless \
  --log-file /private/tmp/warforge_h120_current_all70.log \
  --path godot/ \
  -s tools/self_play_observer.gd \
  -- \
  --runs=10 \
  --strategies=all \
  --difficulty=1 \
  --commander=gambler \
  --talisman=flint \
  --seed=2026073120 \
  --include-results=true \
  --quiet-progress=true \
  --out=/private/tmp/warforge_h120_current_all70.json \
  --trace-dir=/private/tmp/warforge_h120_current_all70_traces
```

Summary:

```text
python3 scripts/summarize_self_play_report.py \
  --report /private/tmp/warforge_h120_current_all70.json \
  --out /private/tmp/warforge_h120_current_all70_summary.md
```

Druid trace analyzer:

```text
python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h120_current_all70_traces \
  --strategy=soft_druid \
  --druid-loss-buckets \
  --druid-active-ledger \
  --druid-spore-tree-gap \
  --druid-run-phase \
  --druid-activation-audit
```

Hard-error log guard:

```text
rg -n "SCRIPT ERROR|Parse Error|ERROR:" /private/tmp/warforge_h120_current_all70.log
```

## Results

PASS self-play observer completed:

```text
schema: warforge-self-play-observer/v1
source: clean main at 932bb8b8d6f87c5b253e4760fece837d28cdaa22
total runs: 70
overall clears: 40/70 (57.1%)
completion readiness: needs_attention
```

Strategy split:

```text
adaptive: 7/10 clears, avg R14.8, avg HP 16.1
aggressive: 9/10 clears, avg R15.0, avg HP 26.4
economy: 5/10 clears, avg R13.9, avg HP 6.1
soft_druid: 0/10 clears, avg R10.1, avg HP -9.2
soft_military: 6/10 clears, avg R12.8, avg HP 15.6
soft_predator: 8/10 clears, avg R14.4, avg HP 15.1
soft_steampunk: 5/10 clears, avg R12.9, avg HP 10.8
```

Completion risks:

```text
high: weak_strategy_floor - soft_druid 0/10 clears, avg R10.1
medium: unlock_burst_pressure - largest run projects 11 raw unlocks, 8 deferred by UI reveal cap
```

PASS summary generated:

```text
/private/tmp/warforge_h120_current_all70_summary.md
```

PASS hard-error log guard:

```text
no SCRIPT ERROR, Parse Error, or ERROR: lines found
```

PASS H105 changed-file boundary:

```text
Result: PASS
Allow records: True
Checked files: 2

Files:
- .claude/traces/experiments/117-current-head-self-play-strategy-floor-refresh.md
- Plans.md
```

PASS whitespace guard:

```text
git diff --check
```

## Druid Diagnosis

soft-Druid summary:

```text
WR: 0.0%
avg final HP: -9.2
avg rounds reached: 10.1
avg buys/run: 23.9
avg rerolls/run: 5.9
levelups/run: 3.3
Lv4 reached: 70.0% (avg R8.1)
Lv5 reached: 60.0% (avg R9.8)
skip reasons: nothing_affordable 103, below_threshold 24, path_lag_hold 31, no_space 2
paths: druid_world_tree 6, druid_garden 3, undetected 1
```

Druid loss buckets:

```text
losses: 10/10
tier_access_lag: 4
payoff_acquisition_lag: 4
path_lag_hold_pressure: 4
combat_conversion_failure: 4
low_druid_board_ratio: 2
payoff_activation_lag: 1
owned_not_active_gap: 1
payoff_no_debuff_conversion: 1
```

Active battle ledger:

```text
scope: R9-R11 focus-active battles
frames: 10 from 10 runs
results: 0 won / 10 lost
primary bottlenecks: debuff_missing 2, enemy_pressure_spike 3, debuff_too_small 5
next signal: Spore is present but under-moving enemy pressure
```

Spore tree-gap audit:

```text
scope: R9-R11 focus-active battles
frames: 10 frames / 10 losses
Spore active: 7 frames, 0 won / 7 lost
tree coverage: 100%
avg Spore own trees: 0.1
avg active Druid trees: 22.9
avg other-Druid trees: 22.7
own/total ratio: 0.4%
Spore-loss current debuff: 15.9%
diagnostic probe debuff: 21.5%
low-own/high-forest losses: zero-own 4, own<=2 and total>=18: 5
low-debuff loss crossings: 5/7
next signal: PACKET_CANDIDATE_FOREST_DEPTH_SPORE_SCALING
```

Run-phase survival:

```text
scope: R8-R12
results: 0 wins / 10 losses
conversion buckets: no_payoff_seen 3, active_no_combat_swing 2, active_too_late 3, offered_not_bought 1, bought_not_active 1
next signal: focus activation commonly happens in the lethal window
```

Activation/promotion audit:

```text
buy runs: 6/10
bought copies: 7
active after buy: 6
never active after buy: 1
avg buy->active: 0.0 rounds
inactive frames: 3 from 2 runs
next signal: activation evidence is mixed; pivot toward Spore pressure conversion or late activation survival
```

## Boundary

No gameplay files were edited for this refresh.

The latest user approval covers only:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

That approval remains real for AI maintenance, but H120 shows the binding M1
strategy-floor problem is not in the AI files. H105 still requires explicit
approval for:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`

Record-only files for this trace:

- `Plans.md`
- `.claude/traces/experiments/117-current-head-self-play-strategy-floor-refresh.md`

## Decision

ADOPT as H120 current-head strategy-floor evidence.

H105 remains the next completion-critical implementation. Do not substitute
another AI-only slice for protected Druid runtime work unless fresh evidence
points away from Spore forest-depth routing.
