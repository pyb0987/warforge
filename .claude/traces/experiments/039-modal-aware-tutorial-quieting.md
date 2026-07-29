# Episode 039: Modal-aware tutorial quieting

Date: 2026-07-27

## Context

H41 moved target-selection instruction/detail labels away from the bottom action
area. H42 made the GUI screenshots lintable and showed one remaining visual
competition issue: tutorial hints were still visible behind active decision
modals, including merge reward choice and target selection.

## Change

`BuildPhase` now listens to target overlay and merge reward popup visibility.
When either decision UI is active, `_refresh_tutorial_hint()` hides the tutorial
panel without marking it dismissed. When the modal closes, the tutorial hint is
refreshed and returns if it is still enabled.

This covers both BuildPhase-owned target selection and GameManager-owned target
selection because the guard listens to the target overlay's own visibility.

## Verification

Focused tutorial suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h43_build_phase_tutorial.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit
  8/8 passed, 21 asserts
```

Focused upgrade target suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h43_build_phase_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  13/13 passed, 82 asserts
```

Screenshot lint unit suite:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots
  7 tests OK
```

Fresh GUI report:

```text
PASS godot --log-file /private/tmp/warforge_h43_gui_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h43_gui_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h43_gui_shots --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=13
```

GUI lint:

```text
PASS python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h43_gui_screenshot_report.json
  PASS live UI screenshot lint: 13 screenshots, 1280x720
```

Modal/tutorial state check:

```text
PASS python3 -c 'import json; d=json.load(open("/private/tmp/warforge_h43_gui_screenshot_report.json")); by={s["label"]:s for s in d["steps"]}; print("merge tutorial visible", by["merge_reward_open"]["layout_rects"]["tutorial_panel"]["visible"]); print("target tutorial visible", by["targeted_boss_reward_target_open"]["layout_rects"]["tutorial_panel"]["visible"]); print("closed tutorial visible", by["targeted_boss_reward_closed"]["layout_rects"]["tutorial_panel"]["visible"]);'
  merge tutorial visible False
  target tutorial visible False
  closed tutorial visible True
```

Live smoke and full suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h43_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  10/10 passed, 279 asserts
PASS git diff --check
PASS godot --headless --log-file /private/tmp/warforge_h43_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1225/1225 passed, 7840 asserts
```

## Decision

Keep H43. The target-selection screenshot no longer shows the tutorial panel
during the decision, and the tutorial returns afterward without changing the
first-run dismissal model.

## Carry-Over

H44 should address growth-chain readability timing. Earlier playtest feedback
said the chain can advance too quickly to read, so the next small completion
slice should make the chain feedback more reviewable without slowing expert
play too much.
