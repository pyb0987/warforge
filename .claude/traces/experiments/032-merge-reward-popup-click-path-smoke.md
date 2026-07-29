# Episode 032: Merge reward popup click-path smoke

## Context

H35 normalized boss reward popup selection around a small public contract:
observe visible choices, select by index, and let the popup own emit/cleanup.

The next decision was whether to build a broader live UI observer immediately or
first harden one more concrete modal. I used the multi-review workflow because
this affects the autonomous testing direction.

Advisory critic convergence:

- False-green/player-realism critic: choose the narrow `UpgradeChoicePopup`
  slice first; broader observer later.
- Implementation-scope critic: add the smallest public upgrade popup API and a
  focused live merge reward smoke.
- Test-maintainability critic: normalize `UpgradeChoicePopup` to the H35
  contract before abstracting a general driver.

## Gap

Before H36:

- `UpgradeChoicePopup` stored choices privately and emitted `upgrade_chosen`
  directly inside `_on_choice_input`.
- Merge reward tests proved the popup was requested, but not that the real
  popup selection/cleanup path worked.
- A test could still pass by mocking the popup or emitting `upgrade_chosen`
  directly while the player-facing popup stayed broken.

## Change

Added the same selection/query surface to `UpgradeChoicePopup`:

- `get_choice_ids()` returns a duplicate of currently displayed upgrade IDs;
- `select_choice_index(idx)` validates an index, emits `upgrade_chosen`, cleans
  the popup, closes it, and returns success/failure;
- mouse input now delegates to `select_choice_index()`.

Added `test_upgrade_choice_popup.gd`:

- valid index emits the selected upgrade and cleans up;
- invalid index emits nothing and leaves the popup open.

Added `test_live_merge_reward_popup_selection_attaches_upgrade` to
`test_game_manager_live_smoke.gd`.

The live smoke:

- starts the real main scene through run start, commander selection, and talisman
  selection;
- seeds two `sp_assembly` copies and buys a third visible shop copy through the
  real shop purchase path;
- lets the real `card_merged` signal open `UpgradeChoicePopup`;
- selects a visible upgrade through `select_choice_index()`;
- asserts the popup closes, choices clear, the exact selected upgrade attaches
  to the ★2 survivor, and build phase remains visible/actionable.

## Verification

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h36_upgrade_choice_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_choice_popup.gd -glog=1 -gexit
  2/2

PASS godot --headless --log-file /private/tmp/warforge_h36_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  9/9

PASS godot --headless --log-file /private/tmp/warforge_h36_build_phase_merge_bonus.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit
  7/7

PASS godot --headless --log-file /private/tmp/warforge_h36_build_phase_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  12/12

PASS godot --headless --log-file /private/tmp/warforge_h36_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  2/2

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h36_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1221/1221
```

## Decision

Keep the H36 change.

Reason:

- It closes the same false-green class H35 closed, now for merge reward upgrades.
- It keeps the popup API small and real: user mouse input and tests share the
  same selection command.
- It proves a player-visible merge reward can be selected, cleaned up, and
  attached to the merged survivor in the live scene.
- Focused and full GUT verification pass.

Carry-over:

- With boss reward and merge reward popups sharing a contract, the next plausible
  completion slice is a small live UI observer/driver helper that records modal
  ownership, visible choices, and actionable control state across early-round
  player flows.
- Keep the observer narrow at first; avoid a broad autoplay harness until it can
  be built from these proven modal primitives.
