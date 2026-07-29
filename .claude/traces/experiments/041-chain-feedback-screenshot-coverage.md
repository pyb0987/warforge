# Episode 041: Chain feedback screenshot coverage

Date: 2026-07-27

## Context

H44 made growth-chain feedback readable in the live flow by adding a bounded
pause, skip support, and a compact last-chain history panel in the following
BUILD phase. The remaining gap was observability: the GUI screenshot/report
pipeline still did not capture the actual CHAIN pause or the last-chain panel.

This meant future visual regressions could pass semantic live smoke while still
being hard to inspect from artifact evidence.

## Change

`live_ui_smoke_report.gd` now scripts a real two-card growth chain after R1
BUILD entry. It records two new ordered snapshots:

- `chain_feedback_open`: CHAIN phase with the event panel, trigger counter, and
  `Complete:` line visible.
- `chain_feedback_last_history`: next BUILD phase with chain feedback hidden and
  the last-chain history panel visible.

`LiveUiProbe.snapshot()` now exports structured details for:

- chain feedback text and event-panel visibility;
- last-chain history text and visibility;
- layout rects for chain panel/counter, last-chain panel, battle status, and top
  HUD labels.

`scripts/lint_live_ui_screenshots.py` now expects 15 screenshot labels and
validates the two new chain frames. It checks the CHAIN log contract, last-chain
panel visibility, last-chain/confirm-button non-overlap, stale battle-status
cleanup, and chain-counter non-overlap against HP/Gold/Terazin HUD labels.

The first v4 visual inspection found that the root-level CHAIN counter overlapped
the top-right Terazin label. I moved `CounterLabel` inside `EventPanel/VBox` and
kept the new lint guard so this stays covered.

`BattlePhase.stop()` now hides and clears its status label so stale battle ticker
text cannot leak into the following BUILD screenshots.

`BuildPhase` last-chain visibility getters now use `is_visible_in_tree()` so
reports match what the player can actually see when the BUILD parent is hidden
under reward UI.

## Verification

Python screenshot-lint unit tests:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots
  11 tests OK
```

Focused ChainVisual suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h45_chain_visual_v5.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit
  8/8 passed, 34 asserts
```

Focused live-scene smoke:

```text
PASS godot --headless --log-file /private/tmp/warforge_h45_live_smoke_v5.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  11/11 passed, 307 asserts
```

Headless semantic report:

```text
PASS godot --headless --log-file /private/tmp/warforge_h45_headless_report_v5.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h45_headless_report_v5.json --commander=gambler --talisman=flint
  ok=true; screenshot_status=disabled
```

GUI screenshot report:

```text
PASS godot --log-file /private/tmp/warforge_h45_gui_screenshot_report_v5.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h45_gui_screenshot_report_v5.json --screenshot-dir=/private/tmp/warforge_h45_gui_shots_v5 --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=15
```

GUI screenshot lint:

```text
PASS python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h45_gui_screenshot_report_v5.json
  PASS live UI screenshot lint: 15 screenshots, 1280x720
```

Formatting and full suite:

```text
PASS git diff --check
PASS godot --headless --log-file /private/tmp/warforge_h45_full_gut_v5.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1229/1229 passed, 7879 asserts
```

## Decision

Keep H45. The live UI smoke workflow now produces screenshot evidence for the
chain feedback that was previously only semantically covered, and the screenshot
review found a real HUD-overlap issue that is now fixed and guarded.

## Carry-Over

H46 should polish the last-chain BUILD panel readability. The panel is now
visible and guarded, but the screenshot shows the history line is cramped and
truncated; the next slice should make the summary/events scannable without
adding a broad visual redesign.
