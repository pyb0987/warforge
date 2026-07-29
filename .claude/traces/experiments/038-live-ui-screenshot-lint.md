# Episode 038: Live UI screenshot lint

Date: 2026-07-27

## Context

H40 added optional GUI screenshots to the live UI smoke report, and H41 used
those screenshots to fix the target-selection overlay placement. The remaining
observability gap was that screenshot evidence still needed manual inspection
for basic artifact health and known UI-state regressions.

## Advisory Review

Three advisory critics converged on the same implementation boundary:

- Treat H42 as screenshot evidence integrity, not broad visual correctness.
- Bind validation to the JSON report path instead of a screenshot directory.
- Use image-derived checks only for PNG health: existence, dimensions, and
  nonblank color range.
- Use structured UI state and rects for semantic/layout checks.
- Keep this out of default headless GUT unless a display is explicitly
  provisioned.

Decision: implement a narrow Python lint and export the needed live UI rects
from the existing probe.

## Change

Added `scripts/lint_live_ui_screenshots.py`.

The lint checks:

- report schema and `ok == true`;
- `metadata.screenshot_status == "enabled"`;
- exact ordered screenshot labels for the current live UI smoke path;
- nested step/final screenshot records matching the top-level screenshot list;
- screenshot path binding to the reported screenshot directory and expected
  filenames;
- PNG readability, recorded dimensions, expected `1280x720` viewport, file
  size, and nonblank color range;
- the known `targeted_boss_reward_target_open` semantic state and exported rects
  so target instruction/detail labels do not overlap the confirm button or
  tutorial panel.

Updated `LiveUiProbe.snapshot()` to include `layout_rects` for key BuildPhase
controls, and documented the lint in `docs/tools/live-ui-smoke-report.md`.

## Verification

Python unit tests:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots
  7 tests OK
```

Old H41 report, expected reject because it predates `layout_rects`:

```text
EXPECTED-FAIL python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h41_gui_screenshot_report.json
  missing valid layout rect: target_instruction / target_detail / confirm_button
```

Focused live smoke:

```text
PASS godot --headless --log-file /private/tmp/warforge_h42_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  10/10 passed, 279 asserts
```

Fresh GUI report:

```text
PASS godot --log-file /private/tmp/warforge_h42_gui_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h42_gui_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h42_gui_shots --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=13
```

Fresh GUI lint:

```text
PASS python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h42_gui_screenshot_report.json
  PASS live UI screenshot lint: 13 screenshots, 1280x720
```

Headless semantic report:

```text
PASS godot --headless --log-file /private/tmp/warforge_h42_headless_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h42_headless_report.json --commander=gambler --talisman=flint
PASS python3 -c 'import json; d=json.load(open("/private/tmp/warforge_h42_headless_report.json")); assert d["ok"] is True; assert d["metadata"]["screenshot_status"] == "disabled"; assert d["screenshots"] == []; step=next(s for s in d["steps"] if s["label"]=="targeted_boss_reward_target_open"); assert step["layout_rects"]["target_instruction"]["visible"] is True; assert step["layout_rects"]["confirm_button"]["visible"] is True; print("headless-report-ok", len(d["steps"]))'
  headless-report-ok 12
```

Headless report lint, expected reject because screenshot lint requires GUI
artifacts:

```text
EXPECTED-FAIL python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h42_headless_report.json
  screenshot_status disabled, 0 screenshots
```

Formatting and full suite:

```text
PASS git diff --check
PASS godot --headless --log-file /private/tmp/warforge_h42_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1223/1223 passed, 7832 asserts
```

## Decision

Keep H42. The project now has a repeatable way to ask whether the latest GUI
screenshot evidence is complete, current-schema, nonblank, and structurally
consistent with the target-selection UI contract.

## Carry-Over

H43 should reduce remaining target-selection visual competition by suppressing
or quieting tutorial hints while modal decision UI is active, then restoring
normal tutorial behavior afterward.
