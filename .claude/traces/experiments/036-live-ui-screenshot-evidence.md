# Episode 036: Live UI screenshot evidence

## Context

H39 closed the semantic targeted-choice smoke gap by proving the live report can
drive a targeted boss reward through the field target overlay. H39's carry-over
recommended adding visual artifacts so layout and overlap issues can be reviewed
without replaying the scene manually.

## Gap

Before H40:

- The report could answer what UI owned input, but not what the UI looked like.
- There was no durable visual artifact linked to semantic step labels.
- Headless report output could not expose layout crowding or overlap.

## Change

Added optional screenshot support to `res://tools/live_ui_smoke_report.gd`.

New behavior:

- `--screenshot-dir=/path` enables PNG capture for each ordered semantic step
  plus the final snapshot.
- Each step snapshot receives a `screenshot` record with label, absolute path,
  width, and height.
- Top-level `screenshots` stores the ordered list.
- `metadata.screenshot_status` is one of:
  - `disabled` when no screenshot dir is passed;
  - `enabled` when screenshot capture is active;
  - `unsupported` when screenshot capture is requested under headless rendering.
- `metadata.display_server` records the active display server.

Headless boundary:

- Godot `--headless` uses the headless/dummy renderer in this environment, so
  viewport textures have no image data.
- The reporter detects that upfront and records one clear unsupported error
  instead of attempting every screenshot and producing repeated texture errors.
- The semantic report path remains headless-friendly when `--screenshot-dir` is
  omitted.

Updated `docs/tools/live-ui-smoke-report.md` with separate commands for:

- headless semantic JSON;
- non-headless screenshot capture.

## Visual Finding

The first successful GUI screenshot run produced 13 PNG artifacts at
`/private/tmp/warforge_h40_gui_shots`.

Manual inspection of:

```text
/private/tmp/warforge_h40_gui_shots/011-targeted_boss_reward_target_open.png
```

showed that target-selection instruction/preview text is now observable, but it
also competes visually with the bottom BUILD COMPLETE/tutorial area. This is not
part of H40's artifact-plumbing acceptance, but it is a useful H41 follow-up.

## Verification

Semantic headless report:

```text
PASS godot --headless --log-file /private/tmp/warforge_h40_live_ui_report_no_shots.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h40_live_ui_report_no_shots.json --commander=gambler --talisman=flint
  ok=true; screenshot_status=disabled; steps=12; screenshots=[]
```

Headless screenshot request:

```text
PASS-EXPECTED-UNSUPPORTED godot --headless --log-file /private/tmp/warforge_h40_headless_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h40_headless_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h40_headless_shots --commander=gambler --talisman=flint
  exit=1; ok=false; screenshot_status=unsupported; one clear error; screenshots=[]
```

GUI screenshot report:

```text
PASS godot --log-file /private/tmp/warforge_h40_gui_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h40_gui_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h40_gui_shots --commander=gambler --talisman=flint
  ok=true; display_server=macOS; screenshot_status=enabled; screenshots=13; each 1280x720
```

JSON/file validation:

```text
PASS python3 -c 'import json; d=json.load(open("/private/tmp/warforge_h40_live_ui_report_no_shots.json")); assert d["ok"] is True; assert d["metadata"]["screenshot_status"] == "disabled"; assert d["screenshots"] == []; assert d["final"]["phase"] == "BUILD"; print("headless-ok", len(d["steps"]))'
  headless-ok 12

PASS python3 -c 'import json; d=json.load(open("/private/tmp/warforge_h40_headless_screenshot_report.json")); assert d["ok"] is False; assert d["metadata"]["screenshot_status"] == "unsupported"; assert d["screenshots"] == []; assert len(d["errors"]) == 1; print("headless-screenshot-unsupported", d["errors"][0])'
  headless-screenshot-unsupported screenshot-dir requires a rendering display; current display server is headless

PASS python3 -c 'import json, os; from pathlib import Path; d=json.load(open("/private/tmp/warforge_h40_gui_screenshot_report.json")); shots=d["screenshots"]; assert d["ok"] is True; assert d["metadata"]["screenshot_status"] == "enabled"; assert len(shots) == 13; assert all(Path(s["path"]).is_file() and os.path.getsize(s["path"]) > 1000 for s in shots); assert all(s["width"] == 1280 and s["height"] == 720 for s in shots); print("gui-shots-ok", len(shots))'
  gui-shots-ok 13

PASS python3 -c 'from PIL import Image, ImageStat; import json; d=json.load(open("/private/tmp/warforge_h40_gui_screenshot_report.json")); p=d["screenshots"][10]["path"]; im=Image.open(p).convert("RGB"); stat=ImageStat.Stat(im); assert im.size == (1280, 720); assert max(stat.var) > 0.0; print("target-shot-nonblank", p)'
  target-shot-nonblank /private/tmp/warforge_h40_gui_shots/011-targeted_boss_reward_target_open.png
```

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h40_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  10/10; 276 asserts

PASS godot --headless --log-file /private/tmp/warforge_h40_build_phase_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  12/12

PASS godot --headless --log-file /private/tmp/warforge_h40_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  2/2

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h40_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1222/1222; 7825 asserts
```

## Decision

Keep the H40 change.

Reason:

- It links visual evidence to the same semantic step labels that already drive
  the report.
- It keeps headless CI semantics intact.
- It makes rendering availability explicit instead of ambiguous.
- It immediately surfaced a real target-overlay layout cleanup opportunity.

Carry-over:

- H41 should use the H40 target overlay screenshot as before-state evidence and
  improve target-selection instruction/preview placement so it does not compete
  with BUILD COMPLETE or tutorial UI.
