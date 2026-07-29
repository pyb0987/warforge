# Episode 026: Manual/live UX smoke chain visibility

## Context

H29 showed that another Steampunk AI behavior probe was the wrong next move:
engine completion improved locally, but `soft_steampunk` and overall outcomes
regressed.

An advisory multi-review recommended moving back to live/manual UX smoke:

- Evidence/balance critic: stop direct Steampunk continuation and inspect the
  D1 live path for the first visible player-facing feedback gap.
- Gameplay design critic: prioritize player-facing payoff/readability over
  proxy AI funnel chasing.
- Implementation/risk critic: avoid another gameplay behavior patch until the
  next bottleneck is observable.

## Smoke Read

Reviewed the run-start → commander/talisman → build → chain/battle path.

Already-covered player-facing items:

- Build HUD shows selected commander and talisman names/status.
- Two-Faced Coin applies effective slot prices and passes `-50%`/`+50%` notes to
  shop card visuals.
- Card-shop reroll does not refresh the upgrade shop unless the phase-level
  refresh explicitly requests it.

Concrete first-run gap found:

- `ChainVisual` starts hidden in `GameManager._ready()`.
- The first `Phase.CHAIN` transition did not explicitly unhide it.
- `ChainVisual` was only set visible after settlement, so the very first BUILD
  could run growth-chain feedback invisibly.

That gap matches the manual playability concern: the player presses BUILD and
can miss the first growth-chain explanation.

## Change

Updated `GameManager._enter_phase(Phase.CHAIN)` to show the chain overlay before
running the growth chain.

Added `chain_feedback_delay_sec` beside the existing test delay knobs so live
smoke can drain the short chain pause without leaving timers alive.

Added `test_live_first_build_shows_chain_feedback_before_battle` to the live
scene smoke:

- starts the real main scene;
- advances through run start, commander selection, and talisman selection;
- places a board card;
- presses BUILD COMPLETE;
- asserts the scene is in `Phase.CHAIN`;
- asserts `ChainVisual` is visible before battle.

## Verification

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h30_live_smoke_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  4/4

PASS godot --headless --log-file /private/tmp/warforge_h30_game_manager_logic.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
  36/36

PASS godot --headless --log-file /private/tmp/warforge_h30_chain_visual_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit
  6/6

PASS godot --headless --log-file /private/tmp/warforge_h30_build_phase_upgrade_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  11/11

PASS godot --headless --log-file /private/tmp/warforge_h30_run_start.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit
  6/6

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h30_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1211/1211
```

## Decision

Keep the H30 change.

Reason:

- It fixes a concrete first-run feedback defect without changing card data,
  difficulty, economy, or AI behavior.
- It expands the live smoke to cover the build-to-chain feedback moment that was
  previously only implied by state transitions.
- Focused and full GUT verification pass.

Carry-over:

- Continue manual/live UX smoke for the next slice before returning to sim
  balance.
- Candidate next smoke areas: boss reward pause/actionability on the first boss
  reward, and whether first-run chain output remains readable when actual
  animated events are present.
