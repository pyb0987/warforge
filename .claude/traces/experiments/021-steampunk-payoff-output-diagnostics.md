# Episode 021: Steampunk payoff output diagnostics

## Context

H24-A proved that blindly activating Steampunk payoffs is unsafe:

```text
H23-B: soft_steampunk 5/20 wins, avg HP 2.75
H24-A: soft_steampunk 3/20 wins, avg HP -2.8
```

The old analyzer could say whether payoffs were bought or active, but not
whether active payoffs had the upstream engine they need.

## H25 Diagnostic Addition

Added Steampunk active-payoff support checks to `scripts/analyze_ai_trace.py`:

```text
sp_warmachine requires active sp_assembly, sp_workshop, sp_line
sp_charger requires active sp_furnace, sp_workshop, sp_circulator
sp_arsenal requires active sp_furnace, sp_workshop, sp_circulator, sp_charger
```

New buckets:

- `payoff_engine_gap`
- `capstone_support_gap`

The analyzer now prints active payoff support-gap counts and includes per-example
missing-card details.

## Verification

```text
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace
```

The test suite now includes a focused Steampunk support-gap fixture for active
Warmachine missing `sp_line` and active Arsenal missing `sp_charger`.

## Trace Read

H23-B baseline:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140_traces --strategy=soft_steampunk --steampunk-loss-buckets
```

```text
soft_steampunk: 5/20 wins
losses: 15/20
active payoff support gaps: payoff engine 0 loss runs, capstone support 0 loss runs
```

H24-A rejected probe:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h24_steampunk_payoff_activation_140_traces --strategy=soft_steampunk --steampunk-loss-buckets
```

```text
soft_steampunk: 3/20 wins
losses: 17/20
payoff_engine_gap: 5
active payoff support gaps: payoff engine 5 loss runs, capstone support 0 loss runs
all 5 payoff_engine_gap losses were in steampunk_spread
examples: active sp_warmachine missing sp_line, sp_workshop, or sp_assembly
```

## Decision

Keep the diagnostic change. It explains the H24 failure mode without touching
gameplay:

- H23 left payoff activation unresolved.
- H24 forced activation and converted that unresolved state into active
  Warmachine-without-engine failures.

Next behavioral work should preserve or complete the Spread engine around
Warmachine instead of simply promoting payoffs to the board.
