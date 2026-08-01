# 128 - H127B Verification Workflow

Date: 2026-08-01

## Context

H127B is blocked on explicit approval for `godot/sim/headless_runner.gd` and
`godot/tests/test_headless_runner.gd`, but the post-approval workflow was still
too manual. H127A made missing Druid contribution snapshots visible, and H127B0
added a boundary guard, so this slice adds an executable workflow and a hard
readiness gate without touching protected simulator files.

## Changes

- Added `scripts/run_h127b_emitter_workflow.py`.
- Added `scripts/check_druid_contribution_ledger_ready.py`.
- Added focused Python tests for both scripts.
- Documented the workflow in the self-play observer tool docs and H127B packet.

## Workflow Contract

Default dry-run:

```bash
python3 scripts/run_h127b_emitter_workflow.py
```

Post-approval execution:

```bash
python3 scripts/run_h127b_emitter_workflow.py --execute
```

Completion-grade execution:

```bash
python3 scripts/run_h127b_emitter_workflow.py --execute --full-gut
```

The workflow runs the H127B boundary guard, focused HeadlessRunner test,
focused Druid snapshot test, analyzer tests, fresh soft-Druid self-play traces,
self-play summary, contribution ledger, readiness gate, and diff whitespace
check. `--full-gut` appends the full Godot test suite.

## Readiness Gate

```bash
python3 scripts/check_druid_contribution_ledger_ready.py \
  /private/tmp/warforge_h127b_druid_emitter60_traces \
  --strategy=soft_druid
```

The gate fails when Druid focus battles exist but snapshots are missing,
malformed, or still produce analyzer blocking signals:

- `SNAPSHOT_EMISSION_REQUIRED`
- `SNAPSHOT_SCHEMA_INVALID`
- `PARTIAL_SNAPSHOT_SCHEMA_INVALID`
- `PARTIAL_SNAPSHOT_COVERAGE`

## Verification

PASS:

```bash
python3 -m unittest \
  scripts.tests.test_check_druid_contribution_ledger_ready \
  scripts.tests.test_run_h127b_emitter_workflow \
  scripts.tests.test_check_h127b_emitter_boundary \
  scripts.tests.test_analyze_ai_trace
```

Observed: `Ran 46 tests ... OK`.

PASS:

```bash
python3 -m py_compile \
  scripts/check_druid_contribution_ledger_ready.py \
  scripts/run_h127b_emitter_workflow.py \
  scripts/check_h127b_emitter_boundary.py \
  scripts/tests/test_check_druid_contribution_ledger_ready.py \
  scripts/tests/test_run_h127b_emitter_workflow.py \
  scripts/tests/test_check_h127b_emitter_boundary.py \
  scripts/tests/test_analyze_ai_trace.py
```

PASS:

```bash
python3 scripts/run_h127b_emitter_workflow.py
```

Observed dry-run includes boundary guard, focused HeadlessRunner test, focused
Druid snapshot test, analyzer tests, fresh self-play traces, summary,
contribution ledger, readiness gate, and diff whitespace check.

PASS:

```bash
python3 scripts/run_h127b_emitter_workflow.py --skip-self-play --full-gut
```

Observed dry-run includes preflight checks plus full GUT without the self-play
trace generation segment.

EXPECTED FAIL:

```bash
python3 scripts/check_druid_contribution_ledger_ready.py \
  /private/tmp/warforge_h104_clean_druid60_traces \
  --strategy=soft_druid
```

Observed old-trace result: 0/129 snapshot coverage, 0 valid focus frames,
81 missing focus snapshots, and blocking signal `SNAPSHOT_EMISSION_REQUIRED`.

## Boundary

No simulator, AI, card data, generated DB, combat, economy, or difficulty files
were edited in this slice. H127B implementation still requires explicit
approval for:

- `godot/sim/headless_runner.gd`
- `godot/tests/test_headless_runner.gd`
