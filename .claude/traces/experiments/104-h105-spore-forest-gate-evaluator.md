# 104 - H105 Spore Forest Gate Evaluator

Date: 2026-07-31
Status: DONE - evaluator only, no gameplay files edited

## Purpose

Add an executable gate wrapper for the H105 Druid Spore forest-depth probe. H105
already defines strict adoption gates, but after implementation the result
should be checked by a repeatable tool rather than by reading prose and eyeballing
trace summaries.

## Changes

- Added `scripts/evaluate_h105_spore_forest_probe.py`.
- Added `scripts/tests/test_evaluate_h105_spore_forest_probe.py`.
- Documented the evaluator in `docs/tools/self-play-observer.md`.

The evaluator imports the existing trace analyzer and applies H105 gates to a
candidate trace directory against the H104 baseline trace directory:

```bash
python3 scripts/evaluate_h105_spore_forest_probe.py \
  /private/tmp/warforge_h105_spore_forest60_traces \
  --baseline-trace-dir=/private/tmp/warforge_h104_clean_druid60_traces
```

## Gate Behavior

The evaluator nominates a same-seed candidate only when all automated H105 gates
move together:

- clears `>=14/60`;
- avg final HP `>= -3.25` and delta `>= +1.0`;
- R9-R11 focus-active WR `>=42.6%` and delta `>= +8pp`;
- H74 screen is not `REJECT_FLAT_OR_NOISY`;
- active-loss enemy survivors `<=12.5`;
- active-loss allied survivors `>=0.2`;
- `debuff_too_small` decreases;
- Spore R9-R11 capped-debuff rate stays below `50%`.

The key false-green guard is covered by tests: if debuff/focus metrics improve
but clears and HP do not, the evaluator returns `REJECT_H105_GATE_FAILURE`.

## Verification

- PASS `python3 -m py_compile scripts/evaluate_h105_spore_forest_probe.py scripts/tests/test_evaluate_h105_spore_forest_probe.py`.
- PASS `python3 -m unittest scripts.tests.test_evaluate_h105_spore_forest_probe -q` (3 tests).
- PASS `python3 scripts/evaluate_h105_spore_forest_probe.py --help`.
- PASS `python3 -m unittest scripts.tests.test_evaluate_h105_spore_forest_probe scripts.tests.test_analyze_ai_trace -q` (25 tests).
- PASS `git diff --check`.

## Boundary

No runtime, card data, generated database, AI, difficulty, economy, or UI files
were edited. H105 still requires fresh approval before implementation.
