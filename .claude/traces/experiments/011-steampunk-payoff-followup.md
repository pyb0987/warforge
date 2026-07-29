# Episode 011: Steampunk focused payoff follow-up

date: 2026-07-02
verdict: adopted-small-positive

## Question

H14 asked for a fixed-evaluator follow-up on one weak focused strategy before
touching difficulty or broad balance numbers. The candidates were
`soft_steampunk` and `soft_druid`.

Sequential multi-review fallback (`FALLBACK_NONINDEPENDENT`) selected
`soft_steampunk` first:

- Design critic: `soft_steampunk` is the lowest focused strategy in the latest
  hardening measurements and has an explicit split between spread and focus
  subpaths in `docs/design/cards-steampunk.md`.
- Evaluator critic: use the existing sim evaluator and `best_genome.json`; do
  not modify `evaluator.gd`, baseline files, card YAML, or difficulty values.
- Risk critic: accept only a small AI-decision patch with 35-run smoke and
  140-run aggregate verification.

## Fixed Evaluator

```text
command:
godot --headless --log-file /private/tmp/godot_h14_140.log --path godot/ -s sim/ai_research/ai_batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json --trace-dir=/private/tmp/warforge_h14_trace_140

genome: res://sim/best_genome.json
runs:   20 per strategy x 7 strategies = 140
seed:   42
trace:  /private/tmp/warforge_h14_trace_140
```

The Godot rotated logger crashed without an explicit log file, matching the H13
diagnosis. All H14 sim commands therefore used `--log-file /private/tmp/...`.

## Baseline Snapshot

```text
weighted_score:       0.5064
card_coverage:        0.2234
activation:           0.8179
per_round_wr_match:   0.6721
theme_ratio_variance: 0.4175
ai_quality_score:     0.7378

soft_steampunk: 3/20 wins, avg_hp -5.60
soft_druid:     4/20 wins, avg_hp -7.95
soft_predator: 12/20 wins, avg_hp 11.95
soft_military: 11/20 wins, avg_hp  6.55
adaptive:      13/20 wins, avg_hp  8.90
economy:        8/20 wins, avg_hp  4.60
aggressive:    15/20 wins, avg_hp 15.50
```

Trace summary for `soft_steampunk`:

```text
avg rounds reached: 11.2
avg buys/run:       37.6
avg rerolls/run:    11.7
skip reasons:       nothing_affordable 244, below_threshold 124, no_space 89
paths:              steampunk_spread 12, steampunk_focus 8
both branch starters bought: 17/20 runs
high-tier SP buys:  sp_barrier 20, sp_line 13, sp_global_workshop 13,
                    sp_arsenal 13, sp_charger 6, sp_warmachine 6
```

## Diagnosis

`docs/design/cards-steampunk.md` defines two subpaths:

- spread: `sp_assembly -> sp_workshop -> sp_line -> sp_warmachine`
- focus: `sp_furnace -> sp_workshop -> sp_circulator -> sp_charger -> sp_arsenal`

The design also calls out a hybrid penalty: taking both T1 branch cores pushes
shared defense/economy cards out of the eight-card field. The baseline trace
showed the AI buying both branch starters in 17/20 `soft_steampunk` runs. This
is not a card-number or difficulty issue; it is an AI path-commitment issue.

## Adopted Change

`godot/sim/ai_build_path.gd` now supports a path-local `anti_penalty`.
Steampunk spread/focus paths use `anti_penalty: 36.0`, while other non-strict
paths keep the default `-12` soft preference. Military strict anti paths remain
at `-50`.

This keeps the change in Layer 2 AI decision-making. It does not change cards,
genome, enemy curves, difficulty, or evaluator files.

## Result

35-run smoke:

```text
before weighted_score:       0.4449
after weighted_score:        0.4599
before soft_steampunk:       0/5 wins, avg_hp -16.6
after soft_steampunk:        1/5 wins, avg_hp  -6.6
```

140-run aggregate:

```text
before weighted_score:       0.5064
after weighted_score:        0.5095
before ai_quality_score:     0.7378
after ai_quality_score:      0.7488
before activation:           0.8179
after activation:            0.8259
before tipping_point_quality:0.0500
after tipping_point_quality: 0.0571

before soft_steampunk:       3/20 wins, avg_hp -5.60
after soft_steampunk:        3/20 wins, avg_hp -3.30
before branch mixing:        17/20 runs bought both branch starters
after branch mixing:         12/20 runs bought both branch starters

unchanged soft_druid:        4/20 wins, avg_hp -7.95
unchanged adaptive:          13/20 wins, avg_hp 8.90
unchanged aggressive:        15/20 wins, avg_hp 15.50
```

The patch is a small positive adoption, not a full strategy fix. It improves
path discipline and average HP but does not increase 140-run `soft_steampunk`
wins. The next steampunk-specific bottleneck is likely payoff timing: shop
level stays around 3 through R11 on average, so T4/T5 payoff cards arrive late
or inconsistently.

## Verification

```text
PASS test_ai_build_path.gd:  28/28
PASS test_ai_agent.gd:       14/14
PASS test_ai_board_eval.gd:  14/14
PASS test_headless_runner.gd:14/14
PASS 35-run fixed evaluator: weighted 0.4599
PASS 140-run fixed evaluator: weighted 0.5095
PASS full GUT: 1157/1157 across 51 scripts, no ObjectDB/resource exit block
```

## Lesson

- Promising next sim axis: payoff timing for `soft_steampunk`, probably level
  advancement or T4/T5 payoff recognition rather than branch commitment.
- Guardrail: avoid further broad AI parameter tuning until the next fixed
  evaluator target is explicit. H14 only justifies the steampunk branch-lock
  change.
- Difficulty remains paused.
