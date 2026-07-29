# Episode 031: Boss reward popup click-path smoke

## Context

H34 proved that R4, R8, and R12 boss reward pauses can all resume the live
scene cleanly. Its carry-over noted one remaining false-green gap: the live
smoke tests selected rewards by directly emitting `reward_selected` and then
manually hiding the popup.

That covered GameManager settlement logic, but it skipped the popup's own
selection and cleanup path.

## Change

Added a small public selection/query surface to `BossRewardPopup`:

- `get_choice_ids()` returns the currently displayed reward IDs;
- `select_choice_index(idx)` validates an index, emits the chosen reward, cleans
  the popup, closes it, and reports success/failure;
- the mouse `gui_input` handler now routes through `select_choice_index()`.

Updated `test_game_manager_live_smoke.gd` so the R4 and R4/R8/R12 live smokes:

- read choices through `get_choice_ids()`;
- select an immediately actionable reward by index through
  `select_choice_index()`;
- assert the popup closes and clears stored choices after selection.

Added `test_boss_reward_popup.gd` as the focused popup contract:

- valid index emits the expected reward and cleans up;
- invalid index emits nothing and leaves the popup open.

## Verification

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h35_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  2/2

PASS godot --headless --log-file /private/tmp/warforge_h35_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  8/8

PASS godot --headless --log-file /private/tmp/warforge_h35_boss_reward.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward.gd -glog=1 -gexit
  70/70

PASS godot --headless --log-file /private/tmp/warforge_h35_game_manager_logic.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
  36/36

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h35_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1218/1218
```

## Decision

Keep the H35 change.

Reason:

- It removes direct test-side signal emission from the live boss reward smoke.
- It proves the popup's own close/cleanup behavior on valid selection.
- It gives future live UI/observer tooling a stable popup action API.
- Focused and full GUT verification pass.

Carry-over:

- Next completion slice should likely generalize this pattern into a small live
  UI observer/driver for modal ownership and actionable controls across the
  first several rounds.
- If keeping an even narrower slice, apply the same public action surface to
  upgrade-choice popup selection before testing merge reward clicks.
