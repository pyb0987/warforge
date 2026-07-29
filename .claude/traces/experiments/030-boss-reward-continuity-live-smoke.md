# Episode 030: Boss reward continuity live smoke

## Context

H31 proved the first R4 boss reward pause/action path. H33's advisory
multi-review left two strong carry-over candidates:

- a broader live UI actionability driver;
- a narrower R4/R8/R12 boss-reward continuity smoke.

I chose the narrower H34 slice first because it directly strengthens the
existing live-run completion evidence while keeping the write surface small.

## Gap

Before H34:

- R4 reward pause/actionability was covered in live smoke.
- R8 and R12 reward pauses were covered indirectly by lower-level reward tests
  and headless paths, but not by a single live scene progressing through all
  three boss reward breaks.
- The final victory smoke jumped directly to R15, so it could not prove that
  intermediate late-run reward modals resume cleanly.

## Change

Added `test_live_boss_reward_continuity_r4_r8_r12` to
`test_game_manager_live_smoke.gd`.

The test:

- starts the real main scene;
- enters build through run start, commander selection, and talisman selection;
- wins R4, R8, and R12 in the same scene;
- asserts each boss reward popup is visible and populated;
- asserts the previous battle-result overlay is cleared before reward choice;
- selects an immediately actionable no-target reward at each boss break;
- asserts each selection settles exactly one round and resumes `Phase.BUILD`;
- asserts the scene ends in player-actionable R13 build with no stale boss
  reward or battle-result popup.

No production code changed in H34.

## Probe Note

The first version of the smoke incorrectly asserted that all three selections
would be retained in `game_state.boss_rewards`. That was a test bug:

- permanent rewards are stored there;
- instant rewards such as `r8_2` are valid choices but are not persistent run
  flags.

I corrected the smoke to track selected reward IDs directly and keep the
invariant focused on continuity/actionability rather than reward persistence.

## Verification

Focused:

```text
FAIL godot --headless --log-file /private/tmp/warforge_h34_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  7/8
  Failure: test incorrectly expected all selected boss rewards to persist in
  game_state.boss_rewards.

PASS godot --headless --log-file /private/tmp/warforge_h34_live_smoke_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  8/8

PASS godot --headless --log-file /private/tmp/warforge_h34_boss_reward.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward.gd -glog=1 -gexit
  70/70

PASS godot --headless --log-file /private/tmp/warforge_h34_headless_rewards.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_rewards.gd -glog=1 -gexit
  17/17

PASS godot --headless --log-file /private/tmp/warforge_h34_game_manager_logic.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
  36/36

PASS godot --headless --log-file /private/tmp/warforge_h34_build_phase_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  12/12

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h34_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1216/1216
```

## Decision

Keep the H34 change.

Reason:

- It strengthens late-run live continuity evidence without changing mechanics,
  card data, economy, difficulty, AI, or UI layout.
- It proves that the R8 and R12 reward breaks behave like the already-covered R4
  path in one scene.
- Focused and full GUT verification pass.

Carry-over:

- The next high-value completion slice is likely a broader live UI
  actionability driver/observer that clicks through real controls and records
  phase/modal ownership across multiple rounds.
- If keeping slices smaller, target boss reward selection through the actual
  popup click path instead of direct signal emission.
