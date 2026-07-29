# Episode 023: Steampunk engine-completion scoring probe

## Context

H26 rejected guarded Steampunk payoff promotion as a true no-op: the AI rarely
reached a state where a payoff was benched while all required engine supports
were already active.

Current H23/H26 Steampunk loss surface:

```text
soft_steampunk: 5/20 wins, avg HP 2.75
loss buckets: tier_access_lag 15/15, payoff_acquisition_lag 11/15,
current_phase_lag 8/15, payoff_activation_gap 4/15,
owned_not_active_gap 4/15, branch_mix 10/15
active current-phase progress: focus 8%, spread 10%
```

## Multi-Review Gate

Three independent critics converged on an upstream acquisition probe:

- Evidence critic: test engine-completion acquisition before activation or card
  buffs.
- Design critic: Steampunk should visibly assemble an authored factory path
  before payoff activation.
- Implementation critic: use a narrow `soft_steampunk` build-path scoring
  modifier; do not change path definitions, card data, promotion, level schedule,
  or reroll reserve.

## Probe

Temporarily added a `+18` Steampunk-local build-path modifier for missing
engine/completion supports:

```text
steampunk_spread: sp_assembly, sp_workshop, sp_line
steampunk_focus: sp_furnace, sp_workshop, sp_circulator
steampunk_focus capstone support: sp_charger
```

The probe explicitly avoided rescuing anti-branch cards and did not target
`sp_barrier`.

Focused temporary tests covered:

- Spread R9 missing `sp_line` gets the late engine-completion bonus.
- Focus R9 missing `sp_circulator` gets the late engine-completion bonus.
- `sp_barrier` keeps only existing shared/current-phase bonuses.
- Focus R12 missing `sp_charger` gets support bonus.
- Full AI scoring prefers missing Spread `sp_line` over shared `sp_barrier`.
- Full AI scoring prefers `sp_warmachine` once Spread engine is complete.

## Verification

Temporary patch:

```text
PASS test_ai_build_path.gd 40/40
PASS test_ai_agent.gd 41/41
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace 11/11
```

Same-seed observer:

```bash
godot --headless --log-file /private/tmp/warforge_h27_steampunk_engine_completion_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h27_steampunk_engine_completion_140.json --trace-dir=/private/tmp/warforge_h27_steampunk_engine_completion_140_traces --quiet-progress=true
```

Analyzer:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h27_steampunk_engine_completion_140_traces --strategy=soft_steampunk --steampunk-loss-buckets
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h27_steampunk_engine_completion_140_traces --diff=/private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140_traces
```

Result versus H23-B:

```text
overall wins: 64/140 unchanged
soft_steampunk: 5/20 unchanged
soft_steampunk avg HP: 2.75 unchanged
Lv4 reached: 55.0% unchanged
Lv5 reached: 30.0% unchanged
loss payoff funnel: offered/affordable/bought 4/4/4 unchanged
payoff_acquisition_lag: 11 unchanged
current_phase_lag: 8 unchanged
branch_mix: 10 unchanged
payoff_engine_gap: 0 unchanged
```

Trace comparison:

```text
7 soft_steampunk trace files differed.
All 7 had identical action sequences.
Differences were score/breakdown/value-only; for example, an already-chosen
sp_circulator buy rose from score 78.8 to 96.8.
```

Post-revert verification:

```text
PASS test_ai_build_path.gd 36/36
PASS test_ai_agent.gd 39/39
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace 11/11
```

## Decision

Reject and revert H27.

Reason:

- The non-noop gate failed: the patch changed scores but did not change any
  same-seed action sequence.
- Engine supports were already chosen when they were available and ranked high
  enough; the binding bottleneck is not ordinary purchase scoring priority.

Carry-over:

- Do not keep raising Steampunk engine support scores blindly.
- The next slice should inspect why required engine/payoff pieces are absent
  despite already being high-priority when offered: offer timing, affordability,
  no-space/bench retention, or loss-before-access are more plausible than raw
  ranking.
