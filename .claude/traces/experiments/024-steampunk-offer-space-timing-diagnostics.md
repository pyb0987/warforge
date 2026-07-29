# Episode 024: Steampunk offer/space timing diagnostics

## Context

H26 and H27 both failed as behavior probes:

- H26 guarded payoff promotion was byte-identical to H23-B.
- H27 engine-completion purchase scoring changed score breakdowns but not action
  sequences.

That made ordinary activation and scoring less plausible as the binding
bottleneck.

## Diagnostic Change

Extended `scripts/analyze_ai_trace.py` Steampunk loss buckets with a path target
funnel for detected Steampunk paths.

Per loss and per category (`engine`, `payoff`, `capstone`), the analyzer now
tracks:

```text
offered, affordable, bought, sold, complete owned, complete active,
missing-final cards, affordable skip reasons
```

Path targets:

```text
steampunk_spread:
  engine: sp_assembly, sp_workshop, sp_line
  payoff: sp_warmachine

steampunk_focus:
  engine: sp_furnace, sp_workshop, sp_circulator
  payoff: sp_charger
  capstone: sp_arsenal
```

Updated `docs/tools/self-play-observer.md` so the new funnel is discoverable
under `--steampunk-loss-buckets`.

## Verification

```text
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace 12/12
```

The new test fixture pins an affordable `sp_line` skipped for `no_space` and a
sold `sp_line` as an engine target funnel issue.

## H23-B Diagnostic Read

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140_traces --strategy=soft_steampunk --steampunk-loss-buckets
```

Key output:

```text
losses: 15/20
loss path target funnel:
  engine: offered 15, affordable 15, bought 15, sold 1,
          complete owned 1, complete active 0, missing-final 14,
          affordable skips {'chosen_other': 44},
          sold cards {'sp_assembly': 1, 'sp_line': 1},
          missing cards {'sp_circulator': 3, 'sp_line': 10, 'sp_workshop': 1}
  payoff: offered 4, affordable 4, bought 4, sold 1,
          complete owned 3, complete active 0, missing-final 12,
          sold cards {'sp_warmachine': 1},
          missing cards {'sp_warmachine': 9, 'sp_charger': 3}
  capstone: offered 0, affordable 0, bought 0,
            missing-final 4, missing cards {'sp_arsenal': 4}
```

## Decision

Keep the diagnostic change.

Reason:

- It explains why H27 score bonuses were action-noops: engine targets are already
  offered, affordable, and bought in every Steampunk loss.
- The binding failure is later in the funnel: complete engine ownership survives
  only 1/15 losses, active engine completion survives 0/15, and `sp_line` is the
  dominant missing engine card.
- Payoffs are a separate offer/access problem: only 4/15 losses ever saw an
  affordable payoff target, and no losing run ended with the payoff target active.

Carry-over:

- Do not keep raising engine purchase scores.
- The next behavior probe should target active-board/retention conversion for
  bought engine pieces, especially Spread `sp_line`, while preserving H23 access
  gains and avoiding blind payoff activation.
