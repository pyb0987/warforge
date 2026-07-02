# Episode 010: Sim diversity triage and bench-space sale fix

date: 2026-07-02
verdict: adopted-small-positive

## Question

After tutorial, achievement, merge, and talisman work, the next autonomous slice
was to identify the weakest non-difficulty path toward a complete playable game.
The open question was whether current sim weakness came from content balance,
strategy diversity, or an AI execution bug.

## Baseline Measurement

Current 140-run baseline:

```text
command:
godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json

weighted_score:       0.4850
card_coverage:        0.2175
activation:           0.8245
per_round_wr_match:   0.5725
theme_ratio_variance: 0.4250

soft_steampunk: 1/20 wins, avg_hp -9.85
soft_druid:     2/20 wins, avg_hp -9.50
soft_predator:  8/20 wins, avg_hp  5.65
soft_military: 10/20 wins, avg_hp  5.95
adaptive:      11/20 wins, avg_hp  7.95
economy:        7/20 wins, avg_hp  5.20
aggressive:    12/20 wins, avg_hp  9.70
```

Smaller 35-run smoke confirmed the same weak strategies:

```text
weighted_score: 0.4281
card_coverage:  0.2104
soft_steampunk: 0/5 wins, avg_hp -17.0
soft_druid:     0/5 wins, avg_hp  -9.8
```

## Diagnosis

Trace batch:

```text
command:
godot --headless --path godot/ -s sim/ai_research/ai_batch_runner.gd -- --genome=res://sim/best_genome.json --runs=5 --seed=42 --baseline=res://sim/baseline.json --trace-dir=/private/tmp/chain-army-h6-steampunk-trace

soft_steampunk: 0/5 wins
avg rounds reached: 11.4
avg buys:           45.6
avg rerolls:        15.8

skip reasons:
nothing_affordable: 54
below_threshold:    34
no_space:           45

detected paths:
steampunk_focus: 1
steampunk_spread: 4

top buys:
sp_assembly 26, sp_workshop 22, ne_wild_pulse 20, ne_earth_echo 16,
sp_furnace 16, sp_circulator 13, sp_interest 13
```

Representative seed:

```text
strategy: soft_steampunk
seed:     772251074
before:   LOSE HP=-17, reached R12
```

The trace exposed a concrete AI bug. While trying to create bench space for a
new purchase, `_sell_weakest_for_upgrade()` could sell a board card. Selling a
board card does not free a bench slot, so the purchase could still fail while
the board had already been damaged. One observed path sold
`sp_global_workshop` from the board before attempting a purchase that still had
no bench room.

## Variants

| Variant | Verdict | Result | Reason |
|---|---|---:|---|
| High-value generic sale guard | REJECT | 140-run weighted 0.4724, coverage 0.1649 | Helped the representative seed but damaged aggregate coverage. |
| Capstone-only guard | REJECT | 35-run weighted 0.4354, soft_steampunk avg_hp -17.8 | Did not address the broad bench-space failure pattern. |
| Bench-only sale restriction | ADOPT | 140-run weighted 0.4903, coverage 0.2195 | Small positive aggregate movement with a clearer invariant. |

## Adopted Change

`godot/sim/ai_agent.gd` now restricts `_sell_weakest_for_upgrade()` to bench
cards when creating purchase space. `_try_buy_best()` passes the incoming score
into the sale helper for trace context, and sale trace events include
`zone: "bench"` and `incoming_score`.

This intentionally does not tune strategy weights or difficulty numbers. It
removes an execution bug in the AI's bench management.

## Result

Representative seed:

```text
strategy: soft_steampunk
seed:     772251074
after:    LOSE HP=-15, reached R13
```

35-run smoke after adoption:

```text
weighted_score: 0.4362
card_coverage:  0.2156
soft_steampunk: 0/5 wins, avg_hp -16.6
```

140-run result after adoption:

```text
weighted_score:       0.4903
card_coverage:        0.2195
activation:           0.8429
per_round_wr_match:   0.6058
theme_ratio_variance: 0.4068

soft_steampunk: 2/20 wins, avg_hp -7.20
soft_druid:     3/20 wins, avg_hp -9.85
soft_predator:  9/20 wins, avg_hp  5.60
soft_military:  9/20 wins, avg_hp  5.95
adaptive:      11/20 wins, avg_hp  7.55
economy:        7/20 wins, avg_hp  4.05
aggressive:    12/20 wins, avg_hp  9.60
```

The adopted fix is small but positive:

```text
weighted_score: 0.4850 -> 0.4903
card_coverage:  0.2175 -> 0.2195
soft_steampunk: 1/20   -> 2/20
soft_druid:     2/20   -> 3/20
```

## Verification

```text
PASS test_ai_agent.gd:      14/14
PASS test_ai_board_eval.gd: 14/14
PASS full GUT:              1139/1139 across 50 scripts
```

Known unrelated warnings remain:

- Batch sims still emit Military `r_conditional` target warnings for
  `self_all` / `self_and_adj_all`.
- Full GUT still exits with existing Godot ObjectDB/resource warnings.

## Lesson

- Promising next axis: clean up the Military target warnings before further sim
  balance changes. They are noisy enough to hide future regression signals.
- Avoid adopting representative-seed wins without aggregate checks. The generic
  high-value guard looked attractive on one seed but clearly regressed coverage.
- The current soft-strategy weakness is not solved. H6 only removed a bench
  management bug and made the next measurement cleaner.
