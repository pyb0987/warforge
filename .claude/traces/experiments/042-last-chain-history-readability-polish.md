# Episode 042: Last-chain history readability polish

Date: 2026-07-27

## Context

H45 added screenshot coverage for the actual growth-chain pause and the
following BUILD last-chain panel. That coverage confirmed the chain panel was
visible, but the BUILD summary was still hard to read because full raw event
lines were cramped into a small one-line label area.

The goal for H46 was to keep the useful "what just happened?" reminder while
making it glanceable during BUILD and guardable by the live UI screenshot lint.

## Change

`BuildPhase` now formats the visible last-chain panel separately from the raw
history:

- raw report text keeps the full event log, including trigger causes, details,
  and the `Complete:` summary;
- visible panel text shows the trigger count plus the two most recent compact
  trigger rows;
- noisy cause prefixes and parenthetical effect details are removed from the
  panel-only display.

The last-chain panel was given enough vertical room for the compact rows while
remaining above the field card area. `LiveUiProbe.snapshot()` now exports both
`text` and `display_text` for last-chain history plus the field container rect.

`scripts/lint_live_ui_screenshots.py` now verifies that the last-chain BUILD
frame:

- preserves `Complete:` in raw history;
- displays compact `#1` and `#2` rows without raw detail markers;
- has enough panel height for those rows;
- avoids overlap with the BUILD complete button and field card area.

## Verification

Focused BuildPhase/tutorial suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h46_build_phase_tutorial_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit
  10/10 passed, 30 asserts
```

Screenshot-lint unit suite:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots
  13 tests OK
```

Focused live-scene smoke:

```text
PASS godot --headless --log-file /private/tmp/warforge_h46_live_smoke_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  11/11 passed, 307 asserts
```

Headless semantic report:

```text
PASS godot --headless --log-file /private/tmp/warforge_h46_headless_report_v2.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h46_headless_report_v2.json --commander=gambler --talisman=flint
  ok=true; screenshot_status=disabled
```

GUI screenshot report:

```text
PASS godot --log-file /private/tmp/warforge_h46_gui_screenshot_report_v2.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h46_gui_screenshot_report_v2.json --screenshot-dir=/private/tmp/warforge_h46_gui_shots_v2 --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=15
```

GUI screenshot lint:

```text
PASS python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h46_gui_screenshot_report_v2.json
  PASS live UI screenshot lint: 15 screenshots, 1280x720
```

Visual inspection:

```text
PASS /private/tmp/warforge_h46_gui_shots_v2/006-chain_feedback_last_history.png
  Compact two-row last-chain summary is visible and sits above the field cards.
```

Full suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h46_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1230/1230 passed, 7884 asserts
```

## Decision

Keep H46. It turns the previous screenshot-observed readability problem into a
small UI improvement plus a reusable screenshot-lint invariant.

## Carry-Over

The next plausible autonomous slice is to use the same live-report workflow to
cover a complete early run loop after player-facing fixes: run-start choices,
shop purchase/merge, chain readability, boss reward, and target reward all now
have screenshot evidence, so the next step should either extend the report one
more round or convert the report output into a short human-readable playtest
summary for faster "what did the bot see?" review.
