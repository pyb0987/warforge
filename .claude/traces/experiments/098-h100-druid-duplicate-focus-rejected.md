# Experiment 098 - H100 Druid Duplicate-Focus Activation Probe

Date: 2026-07-30
Status: REJECTED - rolled back

## Decision

Reject and roll back H100. The protected duplicate-focus activation probe was
safe enough locally, but it produced no same-seed activation or outcome delta
against H94 and failed the packet's adoption gate.

## Scope

User approved protected edits to:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

Implemented probe behavior:

- Allowed `_find_path_focus_replacement()` to consider a duplicate active
  current-focus card as a replacement candidate.
- Kept single active current-focus cards protected.
- Added focused tests for duplicate payoff replacement and single-focus
  protection.

Rollback:

- Reverted only the H100-owned protected edits in the two approved files.
- Did not change card data, generated databases, combat systems, difficulty
  values, economy values, progression thresholds, or other `godot/sim/**` files.

## Local Safety Evidence

Focused pre-screen after patch:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

41/41 passed
```

Focused rollback verification:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

39/39 passed
```

## Same-Seed Screen

Self-play command:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h100_activation60 \
  godot --headless --log-file /private/tmp/warforge_h100_activation60.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=60 --strategies=soft_druid --difficulty=1 \
  --commander=gambler --talisman=flint \
  --seed=2026072901 \
  --out=/private/tmp/warforge_h100_activation60.json \
  --trace-dir=/private/tmp/warforge_h100_activation60_traces \
  --quiet-progress=true
```

Summary:

```text
python3 scripts/summarize_self_play_report.py \
  --report=/private/tmp/warforge_h100_activation60.json \
  --out=/private/tmp/warforge_h100_activation60_summary.md
```

Observed result:

- Clears: 9/60, unchanged from H94.
- Average final HP: -4.23, unchanged from H94.
- Completion readiness: `needs_attention`.
- Top risk: `low_overall_clear_rate`.
- Unlock burst pressure remains a watch item: largest raw projected run 8
  unlocks, UI reveal cap 3, largest deferred 5.

## Analyzer Comparison

Command:

```text
python3 scripts/analyze_ai_trace.py \
  /private/tmp/warforge_h100_activation60_traces \
  --strategy=soft_druid \
  --druid-active-ledger \
  --druid-run-phase \
  --druid-activation-audit \
  --druid-path-lag-audit \
  --druid-compare-baseline=/private/tmp/warforge_h94_druid60_traces
```

Key comparison against H94:

- Run result: 9/60 -> 9/60 clears.
- Average HP delta: +0.00.
- R9-R11 focus ledger WR delta: +0.0%.
- Active-loss survivor margin unchanged.
- Bottleneck deltas all 0.
- Screen verdict: `REJECT_FLAT_OR_NOISY`.
- Run-phase conversion bucket deltas all 0.
- Payoff buy runs: 42/60 -> 42/60.
- Inactive frames: 29 -> 29.
- Bench gaps: 23 -> 23.
- Never active after buy: 17 -> 17.
- Promotion skips: 19 -> 19.
- Path-lag holds: 255 -> 255.
- Candidate path-lag gate remains:
  `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.

## Gate Result

H100 fails the H99 adoption packet because:

- H74 screen remained `REJECT_FLAT_OR_NOISY`.
- No direct activation signal improved:
  - inactive frames did not decrease,
  - bench gaps did not decrease,
  - never-active-after-buy copies did not decrease.
- Run-phase and combat ledger signals were flat.

Non-regression on clears and HP is not enough for adoption.

## Advisory Multi-Review

Three advisory critics converged on rollback:

- Adoption gate critic: `ROLLBACK`, 2/10 keep score. The packet hard-fails
  because the H74 screen is still `REJECT_FLAT_OR_NOISY` and activation signals
  are flat.
- Implementation/boundary critic: `ROLLBACK`, 2/10 keep score. The patch was
  narrow and boundary-safe, but keeping rejected tests would encode a false
  regression requirement.
- Frame-challenge critic: `ROLLBACK`, 9/10. Focused tests are only safety
  evidence; adoption requires same-seed causal trace improvement. A generic
  self-play summary `PASS` means report generation succeeded, not that H100
  passed the gameplay adoption gate.

## Next Slice

Do not retry the duplicate-focus activation probe without new evidence.

The next plausible strategy-floor slice is to pivot from activation mechanics to
R9-R11 combat conversion, especially the active battle ledger signal where
Spore is present but under-moving enemy pressure:

- R9-R11 focus-active battle ledger WR: 34.6%.
- Primary bottleneck: `debuff_too_small` in 30 frames.
- Next signal from analyzer: inspect Spore debuff scaling/caps before more
  activation-policy probes.

If the next slice touches protected `godot/sim/**`, card values, difficulty, or
economy tuning, request fresh approval first.
