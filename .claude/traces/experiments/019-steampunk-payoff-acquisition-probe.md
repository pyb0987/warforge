# Episode 019: Steampunk payoff acquisition probe

## Context

H20/H21/H22 narrowed the Steampunk failure mode:

- H20 baseline: `soft_steampunk` was 5/20 wins, avg HP 2.15, Lv4 reached 20%,
  Lv5 reached 5%, and losing-run payoff funnel was only 1/1/1
  offered/affordable/bought.
- H21 raw tier-access force fixed Lv4/Lv5 timing but regressed survival and
  purchases badly.
- H22 stronger branch lock removed branch mixing but did not improve outcomes or
  payoff acquisition.

H23 target: improve T4/T5 payoff offer/buy conversion without raw early leveling,
card number changes, or hard branch locking.

## Multi-review

Three independent read-only critics reviewed the next probe.

Consensus:

- Do not touch card cost/tier/power yet.
- Do not reuse the H21 full tier-force path.
- Test a Steampunk-local pre-payoff economy/reroll discipline probe.
- Gate adoption on same-seed observer evidence, not on cleaner-looking logic.

Important caveat from reviewers:

- Reject a change that only improves Lv4 access by starving purchases or making
  low-Steampunk-board / activation buckets worse.

## H23-A: Disable Pre-payoff Path Urgency

Patch shape:

```gdscript
if strategy == "soft_steampunk" and (state.shop_level < 4 or state.round_num < 9):
	return result
```

Focused tests:

```text
PASS test_ai_agent.gd 39/39
PASS test_ai_build_path.gd 36/36
PASS scripts.tests.test_analyze_ai_trace 10/10
```

Observer:

```bash
godot --headless --log-file /private/tmp/warforge_h23_steampunk_pre_payoff_reroll_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h23_steampunk_pre_payoff_reroll_140.json --trace-dir=/private/tmp/warforge_h23_steampunk_pre_payoff_reroll_140_traces --quiet-progress=true
```

Result versus H20 baseline:

```text
overall: 64/140 wins unchanged, avg HP 7.84 -> 7.92
soft_steampunk: 5/20 wins unchanged, avg HP 2.15 -> 2.75
soft_steampunk purchases: 45.2 -> 41.0
soft_steampunk rerolls: 15.1 -> 12.7
pre-R9 rerolls: 3.50/run -> 1.05/run
Lv4 reached: 20% -> 55%
Lv5 reached: 5% -> 30%
loss payoff funnel: 1/1/1 -> 4/4/4
payoff_acquisition_lag: 14/15 -> 11/15
no_space_pressure: 10/15 -> 4/15
threshold_pressure: 15/15 -> 14/15
low_steampunk_board_ratio: 2/15 -> 5/15
payoff_activation_gap: 1/15 -> 4/15
```

Decision:

- Partial mechanism success: access and payoff buying improved without H21's
  purchase collapse.
- Not clean enough to adopt as-is because payoff activation and board-ratio
  buckets worsened.

## H23-B: Cap Pre-payoff Path Urgency

Patch shape:

```gdscript
if strategy == "soft_steampunk" and (state.shop_level < 4 or state.round_num < 9):
	result["max_rerolls"] = current_max_rerolls + mini(reroll_bonus, 2)
	return result
```

This keeps a small amount of engine-search pressure but preserves the
pre-payoff gold reserve.

Focused tests:

```text
PASS test_ai_agent.gd 39/39
PASS test_ai_build_path.gd 36/36
PASS scripts.tests.test_analyze_ai_trace 10/10
```

Observer:

```bash
godot --headless --log-file /private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140.json --trace-dir=/private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140_traces --quiet-progress=true
```

Result:

- Top-level and Steampunk bucket metrics matched H23-A.
- 129/140 trace files were byte-identical to H23-A; 11 changed traces were all
  `soft_steampunk`, but aggregate metrics stayed the same.
- The preserved reserve, not the exact cap amount, appears to be the binding
  behavior for this seed set.

## Decision

Adopt H23-B as a narrow access-funnel improvement with a carry-over risk.

Rationale:

- It improves Lv4/Lv5 access and payoff buying without touching card data,
  global difficulty, Druid behavior, branch penalties, or raw tier forcing.
- It avoids the H21 purchase collapse and preserves overall 140-run outcomes.
- It exposes the next failure more clearly: Steampunk now buys payoffs more
  often, but losing runs frequently fail to activate them on board or lack the
  active engine to convert them.

Carry-over:

- H24 should target Steampunk payoff activation/board usage, not more tier
  access.
- Watch `low_steampunk_board_ratio`, `payoff_activation_gap`, and
  `owned_not_active_gap`; H23 must not be treated as final Steampunk balance.
