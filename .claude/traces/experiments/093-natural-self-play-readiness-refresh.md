# 093 - Natural Self-Play Readiness Refresh

Date: 2026-07-30

## Goal

Resume after H96 without crossing the protected simulator edit boundary. Use
natural self-play evidence to refresh the M1 completion-readiness gates and
avoid treating live UI fixture data as progression or strategy viability proof.

## Advisory Review

Decision: choose the next unprotected slice while H78 protected simulator edits
remain approval-gated.

Critic synthesis:

- Product-completion critic: advisory veto on another unprotected tooling slice
  as the primary move; H78 remains the direct M1 blocker.
- Evidence critic: if approval is absent, run a no-edit all-core D1 self-play
  readiness refresh with raw JSON, traces, summary, analyzer output, and a
  protected-boundary check.
- Scope-boundary critic: keep the slice read-only/evidence-only; do not edit
  `godot/sim/**`, generated DB files, card YAML, difficulty, economy, reward,
  or progression thresholds.

Decision: run the no-edit self-play refresh and record its result as evidence,
not as M1 completion.

## Commands

Natural self-play:

```text
godot --headless --log-file /private/tmp/warforge_h97_selfplay70.log --path godot/ -s tools/self_play_observer.gd -- --runs=10 --strategies=all --difficulty=1 --commander=gambler --talisman=flint --seed=2026073001 --out=/private/tmp/warforge_h97_selfplay70.json --trace-dir=/private/tmp/warforge_h97_selfplay70_traces --quiet-progress=true
```

Summary:

```text
python3 scripts/summarize_self_play_report.py --report=/private/tmp/warforge_h97_selfplay70.json --out=/private/tmp/warforge_h97_selfplay70_summary.md
```

Trace diagnostics:

```text
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h97_selfplay70_traces > /private/tmp/warforge_h97_selfplay70_trace_summary.txt
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h97_selfplay70_traces --strategy=soft_druid --druid-loss-buckets --druid-active-ledger --druid-run-phase --druid-path-lag-audit > /private/tmp/warforge_h97_selfplay70_druid_diagnostics.txt
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h97_selfplay70_traces --strategy=soft_druid --druid-loss-buckets --druid-active-ledger --druid-run-phase --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h94_druid60_traces > /private/tmp/warforge_h97_selfplay70_druid_vs_h94.txt
```

## Evidence

Self-play summary:

```text
Verdict: PASS
Total runs: 70
Overall: 36/70 clears (51.4%), avg rounds 13, avg final HP 10.30.
Completion readiness: needs_attention.
Top risk: weak_strategy_floor, soft_druid 0/10 clears, avg R10.4.
Second risk: unlock_burst_pressure, largest run projects 11 raw unlocks; up to 8 deferred by UI reveal cap.
```

Strategy split:

```text
adaptive: 10/10 clears.
aggressive: 10/10 clears.
soft_predator: 5/10 clears.
soft_military: 5/10 clears.
economy: 3/10 clears.
soft_steampunk: 3/10 clears.
soft_druid: 0/10 clears.
```

Boss reward integrity:

```text
R4 reward/eligible: 100.0%.
R8 reward/eligible: 100.0%.
R12 reward/eligible: 100.0%.
```

Unlock projection:

```text
Status: complete.
Runs with projected unlocks: 66.
Largest raw single-run projection: 11.
Reveal pacing model: ui_reveal, cap 3/run.
Deferred in 48 runs; largest deferred 8.
```

Druid diagnostics:

```text
soft_druid WR: 0.0%.
avg final HP: -7.6.
loss buckets: combat_conversion_failure 6/10, path_lag_hold_pressure 6/10.
active battle ledger: 4/16 focus-active R9-R11 battles won.
path-lag audit: 41 holds, 38 no-focus holds (92.7%), 9 actionable no-focus loss runs.
approval gate: GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD.
```

H94 comparison:

```text
H94 baseline soft-Druid: 9/60 clears.
H97 soft-Druid: 0/10 clears.
Comparison verdict: REJECT_FLAT_OR_NOISY.
Candidate approval gate: GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD.
Next signal: protected AI policy probe is justified; do not edit godot/sim/** until the user approves that protected surface.
```

## Decision

ADOPT as evidence only.

H97 does not close M1. It strengthens the current completion gate state:

- overall D1 flow and boss reward application are credible;
- natural unlock burst pressure remains a watch item, not a threshold-change
  mandate;
- strategy viability remains red because soft-Druid is 0/10 in the all-core
  sample;
- the recomputed Druid path-lag evidence again points to H78's protected
  no-focus stabilizer probe.

## Boundary Check

Sensitive boundary:

```text
git status --short -- godot/sim godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/core/data/conscript_pool_data.gd godot/core/difficulty.gd data/cards
```

Result:

```text
PASS no output.
```

Whitespace guard:

```text
git diff --check
```

Result:

```text
PASS.
```

## Next

Request explicit protected approval for H78 before editing `godot/sim/ai_agent.gd`.
If approval is unavailable, do not keep adding tooling as a substitute for
strategy viability; only take another unprotected slice if new manual play
reveals a concrete player-facing defect outside simulator policy.
