# Episode 020: Steampunk payoff activation probe

## Context

H23 improved Steampunk payoff access and buying but exposed a new board-use
question:

```text
H23-B baseline:
overall: 64/140 wins, avg HP 7.92
soft_steampunk: 5/20 wins, avg HP 2.75
Lv4 reached: 55%
Lv5 reached: 30%
loss payoff funnel: 4/4/4
payoff_activation_gap: 4/15
owned_not_active_gap: 4/15
low_steampunk_board_ratio: 5/15
```

Hypothesis: Some bought Steampunk payoffs are not being installed on the active
board, so extending the existing Druid path-focus bench promotion to Steampunk
could improve conversion from acquired payoff to active payoff.

## Multi-review

Three critics reviewed the H24 candidate.

Consensus:

- Run the probe, but do not treat it as a balance fix unless outcomes and
  activation buckets improve together.
- Use the smallest implementation: widen only `_promote_path_focus_bench` from
  `soft_druid` to an exact allow-list including `soft_steampunk`.
- Do not touch scoring, card data, level schedules, reroll policy, or generic
  swap protection.

Design warning:

- Do not install the payoff by selling the engine. Warmachine without Spread
  infrastructure or Charger/Arsenal without Focus infrastructure is visually
  active but still fantasy-dead.

## H24-A: Steampunk Path-focus Bench Promotion

Patch shape:

```gdscript
if strategy != "soft_druid" and strategy != "soft_steampunk":
	return
```

Focused tests added for:

- Focus payoff promotion (`sp_charger`) from bench.
- Spread payoff promotion (`sp_warmachine`) from bench.
- Non-Steampunk no-op regression.

Focused checks before observer:

```text
PASS test_ai_agent.gd 42/42
PASS scripts.tests.test_analyze_ai_trace 10/10
```

Observer:

```bash
godot --headless --log-file /private/tmp/warforge_h24_steampunk_payoff_activation_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h24_steampunk_payoff_activation_140.json --trace-dir=/private/tmp/warforge_h24_steampunk_payoff_activation_140_traces --quiet-progress=true
```

Result versus H23-B:

```text
overall: 64/140 -> 62/140 wins
overall avg HP: 7.92 -> 7.13
soft_steampunk: 5/20 -> 3/20 wins
soft_steampunk avg HP: 2.75 -> -2.8
soft_steampunk purchases: 41.05 -> 40.65
Lv4 reached: 55% -> 50%
Lv5 reached: 30% -> 30%
loss payoff funnel: 4/4/4 -> 5/5/5
owned_not_active_gap: 4/15 -> 1/17
payoff_activation_gap: 4/15 -> 0/17 by current bucket output
```

Additional trace read:

```text
H23 final active payoff runs: 0/20, owned payoff runs: 5/20
H24 final active payoff runs: 5/20, owned payoff runs: 6/20
H24 path_focus_activation promotes: 18
H24 active payoff final cards: sp_warmachine in 5 runs
```

Decision:

- Reject and revert. The probe achieved its mechanical goal but regressed the
  actual game outcome badly.
- Interpretation: payoff activation alone can install a visible payoff while
  weakening the factory around it. The next target is not activation by itself;
  it is payoff output/engine integrity.

Post-revert checks:

```text
PASS test_ai_agent.gd 39/39
PASS scripts.tests.test_analyze_ai_trace 10/10
```

Carry-over:

- H25 should add or use diagnostics for active payoff output context:
  Warmachine with Spread engine/unit/firearm density, Charger with Focus
  manufacture/upgrade engine, and Arsenal with concentration/sell support.
- Avoid broad active-payoff promotion unless it preserves upstream engine cards.
