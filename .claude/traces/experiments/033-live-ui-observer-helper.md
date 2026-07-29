# Episode 033: Live UI observer helper

## Context

H35 and H36 established a small choice-popup contract for two player-facing
reward gates:

- `BossRewardPopup.get_choice_ids()` / `select_choice_index()`;
- `UpgradeChoicePopup.get_choice_ids()` / `select_choice_index()`.

H36's carry-over recommended a narrow live UI observer/driver built from these
modal primitives, rather than jumping directly to a broad autoplay harness.

## Gap

Before H37:

- `test_game_manager_live_smoke.gd` contained useful live-scene checks, but
  modal ownership and actionability assertions were ad hoc.
- Run start, commander, talisman, merge reward, and boss reward actions were not
  reported through one shared observable shape.
- A future "play it yourself" tool would have to infer UI state from scattered
  test code instead of a reusable probe.

## Change

Added `res://tests/live_ui_probe.gd`, a test-side observer/driver helper.

`LiveUiProbe.snapshot(main)` returns a dictionary containing:

- current phase name and round;
- `active_modals`;
- `has_modal`;
- per-modal `choices`;
- per-modal `actionable`;
- visibility of build, chain, battle result, and game-over UI surfaces.

The helper also provides small public-path actions:

- `press_run_start(main)`;
- `select_commander(main, commander_type)`;
- `select_talisman(main, talisman_type)`;
- `select_choice(main, modal_id, idx)` for boss/upgrade choice popups;
- `choice_ids(main, modal_id)` for boss/upgrade choice popups.

Updated `test_game_manager_live_smoke.gd` so the live run-start, merge reward,
and boss reward paths now:

- snapshot modal ownership before acting;
- assert the expected modal is the only active owner;
- assert the modal is actionable;
- select through `LiveUiProbe` rather than reaching directly into the popup from
  every test step.

## Verification

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h37_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  9/9

PASS godot --headless --log-file /private/tmp/warforge_h37_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  2/2

PASS godot --headless --log-file /private/tmp/warforge_h37_upgrade_choice_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_choice_popup.gd -glog=1 -gexit
  2/2

PASS godot --headless --log-file /private/tmp/warforge_h37_run_start_screen.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit
  6/6

PASS godot --headless --log-file /private/tmp/warforge_h37_talisman_select_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman_select_popup.gd -glog=1 -gexit
  4/4

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h37_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1221/1221
```

## Decision

Keep the H37 change.

Reason:

- It turns repeated live UI assertions into a reusable observer vocabulary.
- It keeps the first observer layer test-side and narrow, avoiding premature
  production or autoplay architecture.
- It improves false-green resistance by checking modal ownership and actionability
  before actions are taken.
- Focused and full GUT verification pass.

Carry-over:

- The next plausible completion slice is to promote this observer pattern into a
  small command-line live smoke/report tool that can emit JSON snapshots for a
  short scripted run.
- Keep the script readably bounded: run start, one build/merge reward event, and
  one boss reward event are enough before considering broader autoplay.
