# Episode 027: First boss reward live UX smoke

## Context

H30 fixed the first build-to-chain feedback gap and left two likely live-smoke
areas:

- first boss reward pause/actionability after the R4 battle;
- readability when actual animated chain events are present.

I chose the first boss reward slice because it is a modal transition on the main
run path. If the player wins R4 and the reward is not clearly actionable, the
run can appear stuck even though the underlying systems are correct.

## Smoke Read

The existing live smoke covered:

- run start into build;
- first build chain feedback;
- battle result, settlement, and game-over meta save;
- final-round victory meta save.

It did not cover the first R4 reward pause. Reading
`GameManager._on_battle_finished()` also showed that the battle result popup was
shown, delayed, and then left visible while the next state could open another
modal. In normal play the delay makes this less obvious, but in test-zero-delay
and fast UI paths it can create overlapping or stale modal state.

## Change

Updated `GameManager._on_battle_finished()` to explicitly hide
`battle_result_popup` after its display delay and before any later state such as
game over, boss reward selection, settlement, or victory.

Added `test_live_first_boss_reward_pause_is_visible_and_actionable` to the live
scene smoke:

- starts the real main scene;
- advances through run start, commander selection, and talisman selection;
- sets up an R4 win with one board card;
- asserts that the boss reward popup is visible and populated;
- asserts that the battle result popup has been cleared;
- emits an immediately actionable reward selection;
- asserts that the game settles R4 and resumes R5 build.

## Verification

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h31_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  5/5

PASS godot --headless --log-file /private/tmp/warforge_h31_game_manager_logic.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
  36/36

PASS godot --headless --log-file /private/tmp/warforge_h31_boss_reward.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward.gd -glog=1 -gexit
  70/70

PASS godot --headless --log-file /private/tmp/warforge_h31_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  11/11

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h31_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1212/1212
```

## Decision

Keep the H31 change.

Reason:

- It fixes a concrete modal clarity risk in the main live play path.
- It adds coverage for the first boss reward moment without touching card data,
  economy, difficulty, AI tuning, or reward balance.
- Focused and full GUT verification pass.

Carry-over:

- Continue the live/manual UX-smoke track.
- Candidate next smoke area: chain output readability when the board has actual
  growth events, especially whether the player can understand what changed
  before combat starts.
