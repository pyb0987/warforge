# Episode 043: Live UI playtest summary

Date: 2026-07-27

## Context

H44-H46 made growth-chain feedback readable and observable through the live UI
smoke report, GUI screenshots, screenshot lint, and a compact last-chain BUILD
panel. The remaining workflow gap was consumption: after Codex "plays" the live
UI, the raw JSON and screenshots are useful but slow to read.

The next-slice decision used advisory multi-review:

- Player-facing UX critic preferred battle aftermath clarity, warning that
  report-only work can pass while players still lack combat explanation.
- Observability/workflow critic recommended a generated human-readable playtest
  summary derived from structured JSON and bound to screenshot lint.
- Engineering-risk critic also recommended the summary first because it is
  read-only, low-touch, and improves review speed without destabilizing the
  currently passing game.

I chose the summary workflow for H47 and carried battle aftermath clarity as the
next likely player-facing candidate.

## Change

Added `scripts/summarize_live_ui_report.py`, a read-only CLI that:

- reads a `warforge-live-ui-smoke/v1` JSON report;
- validates the expected ordered smoke labels;
- checks that the final state is clean BUILD;
- checks required chain, merge reward, boss reward, and targeted reward fields;
- optionally reruns `lint_live_ui_screenshots.validate_report()` against the
  same report path via `--lint-screenshots`;
- writes a compact Markdown playtest summary with run selection, final state,
  covered moments, key screenshot paths, evidence fields, and issues.

Added `scripts/tests/test_summarize_live_ui_report.py` for the summary layer and
documented the command in `docs/tools/live-ui-smoke-report.md`.

## Verification

Summary unit tests:

```text
PASS python3 -m unittest scripts.tests.test_summarize_live_ui_report
  6 tests OK
```

Real GUI report summary with screenshot lint recomputed from the same report:

```text
PASS python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h46_gui_screenshot_report_v2.json --lint-screenshots --out /private/tmp/warforge_h47_live_ui_summary.md
```

Generated summary excerpt:

```text
Verdict: PASS
Screenshots: enabled (15 records)
Screenshot lint: PASS
Chain feedback paused in CHAIN with Triggers: 2
Final state: BUILD R5, modal-free yes
```

Headless report summary:

```text
PASS python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h46_headless_report_v2.json --out /private/tmp/warforge_h47_live_ui_headless_summary.md
```

Combined Python checks:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_summarize_live_ui_report
  19 tests OK

PASS python3 -m py_compile scripts/summarize_live_ui_report.py
```

Formatting:

```text
PASS git diff --check
```

## Decision

Keep H47. It makes the existing self-play observability useful to a human
reviewer, and it recomputes claims from the source report instead of trusting a
hand-authored playtest note.

## Carry-Over

The strongest next player-facing slice is battle aftermath clarity. The current
workflow can now generate a compact "what Codex saw" note, so the next UI
improvement can be grounded in those summaries and screenshots: after combat,
show clearer HP before/after, enemy survivor/damage context, reward gold, and a
short next-build hint without changing difficulty or combat balance.
