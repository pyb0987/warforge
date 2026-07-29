# Episode 037: Target overlay layout cleanup

Date: 2026-07-27

## Context

H40 added optional GUI screenshot artifacts to the live UI smoke report. Visual
inspection of the targeted boss reward frame showed that the target-selection
detail/instruction labels were positioned in the same bottom area as BUILD
COMPLETE and the tutorial prompt.

Before-state screenshot:

```text
/private/tmp/warforge_h40_gui_shots/011-targeted_boss_reward_target_open.png
```

## Change

Moved `TargetSelectOverlay/DetailLabel` and `TargetSelectOverlay/InstructionLabel`
into the open middle band of the build board. Added a focused BuildPhase test
that asserts both overlay labels avoid the bottom confirm button and tutorial
panel while a pending upgrade target selection is open.

Also fixed the live UI probe snapshot return indentation so the existing smoke
report can parse and run reliably.

After-state screenshot:

```text
/private/tmp/warforge_h41_gui_shots/011-targeted_boss_reward_target_open.png
```

## Verification

Focused overlay suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h41_build_phase_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  13/13 passed, 82 asserts
```

Live smoke suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h41_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  10/10 passed, 276 asserts
```

GUI screenshot report:

```text
PASS godot --log-file /private/tmp/warforge_h41_gui_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h41_gui_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h41_gui_shots --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=13; each 1280x720
```

Screenshot artifact validation:

```text
PASS python3 -c 'import json, os; from pathlib import Path; from PIL import Image, ImageStat; d=json.load(open("/private/tmp/warforge_h41_gui_screenshot_report.json")); shots=d["screenshots"]; assert d["ok"] is True; assert d["metadata"]["screenshot_status"] == "enabled"; assert len(shots) == 13; assert all(Path(s["path"]).is_file() and os.path.getsize(s["path"]) > 1000 for s in shots); assert all(s["width"] == 1280 and s["height"] == 720 for s in shots); p=shots[10]["path"]; im=Image.open(p).convert("RGB"); stat=ImageStat.Stat(im); assert im.size == (1280,720); assert max(stat.var) > 0.0; print("gui-shots-ok", len(shots)); print("target-shot-nonblank", p)'
  gui-shots-ok 13
  target-shot-nonblank /private/tmp/warforge_h41_gui_shots/011-targeted_boss_reward_target_open.png
```

Formatting and full suite:

```text
PASS git diff --check
PASS godot --headless --log-file /private/tmp/warforge_h41_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1223/1223 passed, 7829 asserts
```

## Decision

Keep the H41 layout change. The after screenshot is not final art, but the
instruction/detail text is now readable without competing with the bottom action
area.

## Carry-Over

H42 should add a lightweight screenshot-derived lint after GUI smoke generation.
Start with narrow checks that are robust to game content variance: screenshot
presence, dimensions, nonblank variance, required labels, and known UI-band
overlap constraints for the target-selection frame.
