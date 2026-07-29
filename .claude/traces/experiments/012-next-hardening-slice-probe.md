# Episode 012: Next hardening slice probe

date: 2026-07-02
verdict: no-code-adopt

## Question

After H10-H15 closed the immediate reward/flow, live smoke, resource-warning,
focused-steampunk, and visual-polish slices, choose the next autonomous
hardening direction.

Sequential multi-review fallback (`FALLBACK_NONINDEPENDENT`) selected a small
`soft_steampunk` payoff-timing probe before starting a new manual UX slice:

- Playability critic: H10-H15 already made the promised live rewards visible,
  added end-to-end smoke, and improved chain/merge feedback. The next UX slice
  needs manual observation to avoid inventing a vague polish task.
- Sim critic: H14 left a concrete fixed-evaluator bottleneck: `soft_steampunk`
  reaches T4/T5 payoffs late or inconsistently.
- Risk critic: only Layer 2 AI decision behavior may be touched. Do not change
  card data, difficulty, genome, evaluator, or baseline files. Adopt only if a
  35-run smoke improves the target and aggregate, then expand to 140 runs.

## Fixed Evaluator

```text
command:
godot --headless --log-file /private/tmp/h16_baseline.log --path godot/ -s sim/ai_research/ai_batch_runner.gd -- --genome=res://sim/best_genome.json --runs=5 --seed=42 --baseline=res://sim/baseline.json --trace-dir=/private/tmp/warforge_h16_baseline_trace

genome: res://sim/best_genome.json
runs:   5 per strategy x 7 strategies = 35
seed:   42
```

## Baseline Snapshot

```text
weighted_score:       0.4599
ai_quality_score:     0.7538
soft_steampunk:       1/5 wins, avg_hp -6.6
soft_druid:           1/5 wins, avg_hp -1.4
```

Trace summary for `soft_steampunk`:

```text
actual shop levels:
- representative win: Lv2 through R7, Lv3 R8, Lv4 R9-R12, Lv5 R13+
- losing runs often stayed Lv2 through R8-R9, with one no-high-tier-buy run

skip reasons across 5 runs:
nothing_affordable 72, below_threshold 32, no_space 25
```

Diagnosis: the H14 "T4/T5 timing" hypothesis is real, but the immediate cause
is not simply a late levelup schedule. Midgame interest reserve can delay
scheduled levelups, but paying that reserve down too early risks board-strength
loss.

## Variant A: Early catch-up levelup reserve

Temporary patch:

```text
soft_steampunk.catchup_levelup_round = 7
soft_steampunk.catchup_levelup_reserve = 8
```

Result:

```text
weighted_score: 0.4599 -> 0.4554
soft_steampunk: 1/5 avg_hp -6.6 -> 0/5 avg_hp -9.0
```

Verdict: REJECT. The patch made some levelups arrive earlier, but damaged
midgame survivability and lost the representative baseline win.

## Variant B: Late conservative catch-up levelup reserve

Temporary patch:

```text
soft_steampunk.catchup_levelup_round = 9
soft_steampunk.catchup_levelup_reserve = 12
```

Result:

```text
weighted_score: 0.4599 -> 0.4599
soft_steampunk: 1/5 avg_hp -6.6 -> 1/5 avg_hp -6.6
```

Verdict: REJECT/NO-OP. The conservative version did not move the fixed smoke
metric, so keeping the helper/config would add complexity without evidence.

## Conclusion

No code was adopted from H16. The shallow "lower levelup reserve when behind"
family is not the right fix by itself. A future sim pass should either:

- add better trace instrumentation for levelup decisions and board-strength
  tradeoffs before changing behavior, or
- test a different axis such as payoff-card valuation, transition-board
  replacement, or strategy-specific shop/reroll behavior with the same fixed
  evaluator.

