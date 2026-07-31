# 106 - H105 Spore Forest Workflow Runner

Date: 2026-07-31
Status: DONE - workflow runner only, no gameplay files edited

## Purpose

Add a dry-run-first command runner for the H105 Druid Spore forest-depth
protected probe. H105 now has a packet, preflight, gate evaluator, and changed-
file boundary guard; the runner makes the eventual approved probe reproducible
without copying commands by hand.

## Changes

- Added `scripts/run_h105_spore_forest_workflow.py`.
- Added `scripts/tests/test_run_h105_spore_forest_workflow.py`.
- Documented the runner in `docs/tools/self-play-observer.md`.

Default safe usage:

```bash
python3 scripts/run_h105_spore_forest_workflow.py
```

This prints the command list. It does not run Godot or self-play unless
`--execute` is supplied.

Execution usage after protected implementation:

```bash
python3 scripts/run_h105_spore_forest_workflow.py --execute
```

The workflow includes:

- source-state check;
- codegen parity;
- card spawn guard;
- focused Druid runtime tests;
- focused ChainEngine tests;
- same-seed H105 self-play;
- self-play summary;
- Druid analyzer with active ledger, Spore tree-gap, run-phase, activation, and
  H104 comparison;
- H105 gate evaluator;
- H105 changed-file boundary guard;
- whitespace diff check.

The H105 evaluator command is marked non-fatal in the runner, because a reject
is an expected and useful outcome that should still be followed by boundary and
diff checks.

## Verification

- PASS `python3 -m py_compile scripts/run_h105_spore_forest_workflow.py scripts/tests/test_run_h105_spore_forest_workflow.py`.
- PASS `python3 -m unittest scripts.tests.test_run_h105_spore_forest_workflow -q` (4 tests).
- PASS `python3 -m unittest scripts.tests.test_run_h105_spore_forest_workflow scripts.tests.test_evaluate_h105_spore_forest_probe scripts.tests.test_check_h105_spore_forest_boundary -q` (13 tests).
- PASS `python3 scripts/run_h105_spore_forest_workflow.py --skip-self-play`.
- PASS `python3 scripts/run_h105_spore_forest_workflow.py --help`.
- PASS `git diff --check`.

## Boundary

No runtime, card data, generated database, AI, difficulty, economy, or UI files
were edited. H105 still requires fresh approval before implementation.
