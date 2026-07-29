# Episode 045: Post-settlement BUILD recap

Date: 2026-07-27

## Context

H48 made the battle result popup explain combat aftermath and explicitly tell
the player that the next step is returning to BUILD after income. The remaining
gap was the income step itself: when BUILD resumed, the HUD totals changed, but
the screen did not explain base income, interest, or Terazin gains.

Difficulty tuning stayed paused. This slice targeted comprehension and
observability only; it did not change card data, combat math, enemy tuning,
economy values, or reward effects.

## Advisory Multi-Review

Three critics reviewed the next-slice choice:

- Player UX critic: score 9, choose post-settlement recap. Settlement happens
  every round, while boss reward comparison is episodic and already has a modal.
- Engineering/Test Risk critic: score 8, choose post-settlement recap. The
  source values already exist in `_run_settlement()`, and the existing
  post-battle BUILD snapshot can verify it.
- Game Loop/Systems critic: score 9, choose post-settlement recap. It completes
  the cadence taught by H48: battle result -> income -> next BUILD.

Decision: implement H49 as a compact `LAST SETTLEMENT` recap sourced from
`GameManager._run_settlement()` values, shown on the BUILD surface without a
new pause or modal.

## Change

`GameManager._run_settlement()` now records a structured recap dictionary after
applying the existing settlement math and before entering the next BUILD. The
recap includes:

- settlement round and next round;
- gold before/after, delta, base income, interest, and interest basis;
- Terazin before/after, delta, base round gain, and commander bonus;
- last battle result flag.

`BuildPhase` renders this as a compact `LAST SETTLEMENT` panel in the existing
right-side tutorial lane. A fresh settlement recap suppresses the tutorial in
that lane; target selection and merge-reward decision UI still hide the recap,
matching the modal-aware quieting pattern from earlier slices. The recap clears
when the next chain starts.

`LiveUiProbe.snapshot()` now exports `last_settlement_recap` text/data and the
`settlement_recap_panel` rect. The command-line live UI report records
`events.settlement_recap` from the post-battle BUILD frame. The screenshot lint
requires the recap text/source fields and checks that the recap does not overlap
tutorial, last-chain, field, or BUILD complete controls. The playtest summary
now reports the exact settlement recap that Codex saw.

## Verification

Focused BuildPhase GUT:

```text
PASS godot --headless --log-file /private/tmp/warforge_h49_build_phase_tutorial.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit
  12/12 passed, 44 asserts
```

Python summary/lint tests:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_summarize_live_ui_report
  24 tests OK

PASS python3 -m py_compile scripts/summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Live-scene smoke:

```text
PASS godot --headless --log-file /private/tmp/warforge_h49_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  12/12 passed, 339 asserts
```

Headless semantic report and summary:

```text
PASS godot --headless --log-file /private/tmp/warforge_h49_headless_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h49_headless_report.json --commander=gambler --talisman=flint
  ok=true; screenshot_status=disabled; events include settlement_recap

PASS python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h49_headless_report.json --out /private/tmp/warforge_h49_headless_summary.md
  summary reports: LAST SETTLEMENT R1 | Gold: 11 -> 18 (+7; +5 income, +2 interest) | Terazin: 2 -> 4 (+2; +2 round) | Next: R2 BUILD
```

GUI screenshot report, lint, and visual inspection:

```text
PASS godot --log-file /private/tmp/warforge_h49_gui_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h49_gui_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h49_gui_shots --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=16

PASS python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h49_gui_screenshot_report.json
  PASS live UI screenshot lint: 16 screenshots, 1280x720

PASS python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h49_gui_screenshot_report.json --lint-screenshots --out /private/tmp/warforge_h49_gui_summary.md

PASS visual inspection /private/tmp/warforge_h49_gui_shots/007-chain_feedback_last_history.png
  The settlement recap sits above the last-chain panel in the right-side lane,
  the tutorial panel is hidden, and neither recap overlaps the field or BUILD
  complete controls.
```

Formatting and full suite:

```text
PASS git diff --check

PASS godot --headless --log-file /private/tmp/warforge_h49_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1235/1235 passed, 7944 asserts
```

## Decision

Keep H49. It closes the H48 follow-through gap by making the every-round
settlement step visible and auditable without changing gameplay values.

## Carry-Over

Boss reward comparison remains a plausible next player-facing slice. The live
observer currently records boss reward IDs and actionability, but not rendered
reward-card comparison text; add that observability before changing the reward
card layout.
