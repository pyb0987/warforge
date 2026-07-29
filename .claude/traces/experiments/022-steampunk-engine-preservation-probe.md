# Episode 022: Steampunk engine-preserving payoff promotion probe

## Context

H24 showed that blindly promoting Steampunk payoffs to the active board regressed
outcomes:

```text
H23-B: soft_steampunk 5/20 wins, avg HP 2.75
H24-A: soft_steampunk 3/20 wins, avg HP -2.8
```

H25 then explained the regression with active payoff support diagnostics:
H24-A created 5 `payoff_engine_gap` loss runs, all Spread/Warmachine cases.

## Multi-Review Gate

Three independent critics reviewed the H26 direction before behavior changes:

- Evidence critic: proceed only as a narrow reversible probe; reject if it
  merely suppresses activation or fails the H23 access gates.
- Design critic: the fantasy fit is strong if framed as factory integrity, not
  a full Steampunk balance fix.
- Implementation critic: conditionally approve only if replacement candidates
  are filtered before selection and promotion is limited to explicit
  payoff/capstone ids.

## Probe

Tested a temporary `soft_steampunk` widening of `_promote_path_focus_bench` with
engine-preserving requirements:

```text
sp_warmachine requires active sp_assembly, sp_workshop, sp_line
sp_charger requires active sp_furnace, sp_workshop, sp_circulator
sp_arsenal requires active sp_furnace, sp_workshop, sp_circulator, sp_charger
```

Focused tests for the temporary patch covered:

- Warmachine promotion with full Spread engine.
- Warmachine blocked when `sp_line` is missing.
- Warmachine blocked when promotion would replace a required engine card.
- Charger promotion with full Focus engine.
- Arsenal blocked without active Charger.
- Barrier excluded from this payoff-only promotion path.

## Verification

Temporary patch:

```text
PASS test_ai_agent.gd 45/45
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace 11/11
```

Same-seed observer:

```bash
godot --headless --log-file /private/tmp/warforge_h26_steampunk_engine_guard_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h26_steampunk_engine_guard_140.json --trace-dir=/private/tmp/warforge_h26_steampunk_engine_guard_140_traces --quiet-progress=true
```

Analyzer:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h26_steampunk_engine_guard_140_traces --strategy=soft_steampunk --steampunk-loss-buckets
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h26_steampunk_engine_guard_140_traces --diff=/private/tmp/warforge_h23b_steampunk_pre_payoff_cap_140_traces
```

Result:

```text
overall wins: 64/140 unchanged
soft_steampunk: 5/20 unchanged
soft_steampunk avg HP: 2.75 unchanged
Lv4 reached: 55.0% unchanged
Lv5 reached: 30.0% unchanged
loss payoff funnel: offered/affordable/bought 4/4/4 unchanged
payoff_activation_gap: 4 unchanged
owned_not_active_gap: 4 unchanged
payoff_engine_gap: 0 unchanged
```

`diff -qr` between H23-B and H26 trace directories produced no output, meaning
the 140 trace files were byte-identical. The temporary patch did not fire in the
measured surface.

Post-revert verification:

```text
PASS test_ai_agent.gd 39/39
PASS python3 -m unittest scripts.tests.test_analyze_ai_trace 11/11
```

## Decision

Reject and revert H26.

Reason:

- The probe was safe but a true no-op on the same-seed 140-run observer.
- The non-noop acceptance gate failed: support-complete active payoff/capstone
  runs did not increase, and activation buckets did not improve.
- The useful finding is diagnostic: Steampunk does not currently reach
  "payoff on bench with full active engine" often enough for guarded promotion
  to matter.

Carry-over:

- Do not return immediately to promotion rules.
- The next Steampunk work should target the upstream engine/acquisition gap:
  the AI must more often own and keep the required engine pieces plus payoff,
  not merely decide whether to activate a support-ready payoff.
