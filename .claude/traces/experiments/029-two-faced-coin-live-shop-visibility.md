# Episode 029: Two-Faced Coin live shop visibility

## Context

H30-H32 improved live-run feedback around the growth chain and the first boss
reward. For H33, I ran an advisory multi-review to choose the next slice.

Summary:

| Critic | Score | Recommendation | Key Risk |
|--------|-------|----------------|----------|
| Player-facing UX | 8 | Make Two-Faced Coin shop modifiers unmistakable in live build UI. | Passing phase smokes while the player cannot tell which shop card is discounted or surcharged. |
| Completion observability | 8 | Build a broader live-run UI driver/observer. | False confidence from headless/self-play passing while live UI actionability is unproven. |
| Implementation risk | 9 | Add an R4/R8/R12 boss-reward continuity smoke. | R15 jump tests can miss intermediate modal dead ends. |

Synthesis:

- Keep the live-run evidence track.
- Choose the Two-Faced Coin slice first because it directly matches prior manual
  player feedback and is small enough to complete without touching balance.
- Carry forward the broader live UI driver and R8/R12 continuity smoke as
  candidates for later slices.

## Gap

Two-Faced Coin math already existed and lower-level tests covered discounted and
surcharged prices.

However:

- the modified card face only appended a small `-50%`/`+50%` suffix;
- live smoke did not prove that selecting Two-Faced Coin produced visible
  modified shop slots;
- the first H33 live smoke exposed a real refresh defect: shop card faces had
  Coin slots, but the HUD identity/status line still showed generic
  `1장 -50%, 1장 +50%` text instead of the rolled slot numbers on initial build
  entry.

## Change

Updated `CardVisual` shop display:

- Coin-modified shop cards now show `COIN -50%` or `COIN +50%` in the face text.
- Coin-modified shop cards get a thicker green/red border.
- Added small getters so live/UI tests can assert the visible shop-note contract.

Updated build-entry display refresh:

- Added `BuildPhase.refresh_display()`.
- `GameManager._enter_phase(Phase.BUILD)` now refreshes the build display after
  build-entry state resets and shop refresh, keeping commander/talisman HUD
  status synchronized with freshly rolled Coin slots.

Added tests:

- `test_live_two_faced_coin_marks_discount_and_markup_shop_slots` starts the real
  main scene, selects Two-Faced Coin, and asserts both modified shop slots are
  visible and marked before purchase.
- `test_shop_card_visual_marks_two_faced_coin_slots` pins the BuildPhase-level
  card-face text and border affordance.

## Verification

Initial probe:

```text
FAIL godot --headless --log-file /private/tmp/warforge_h33_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  6/7 passed
  Failure: live Two-Faced Coin cards had slot notes, but IdentityLabel did not
  include the rolled discount/markup slot numbers.
```

Focused after fix:

```text
PASS godot --headless --log-file /private/tmp/warforge_h33_live_smoke_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  7/7

PASS godot --headless --log-file /private/tmp/warforge_h33_build_phase_upgrade_shop_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  12/12

PASS godot --headless --log-file /private/tmp/warforge_h33_shop_logic_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_shop_logic.gd -glog=1 -gexit
  46/46

PASS godot --headless --log-file /private/tmp/warforge_h33_talisman_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman.gd -glog=1 -gexit
  38/38

PASS godot --headless --log-file /private/tmp/warforge_h33_game_manager_logic.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
  36/36

PASS godot --headless --log-file /private/tmp/warforge_h33_build_phase_tutorial.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit
  6/6

PASS godot --headless --log-file /private/tmp/warforge_h33_build_phase_merge_bonus.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit
  7/7

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h33_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1215/1215
```

## Decision

Keep the H33 change.

Reason:

- It resolves a concrete player-facing affordance gap without changing talisman
  math, card data, economy, difficulty, combat, or AI behavior.
- The live smoke now proves the actual run-start talisman selection produces
  visible discounted and surcharged shop slots before purchase.
- The initial failing smoke caught and fixed stale HUD status after shop refresh.

Carry-over:

- Consider a broader live-run actionability driver that clicks through real UI
  controls and logs modal/phase ownership over multiple rounds.
- Consider an R4/R8/R12 boss-reward continuity smoke before returning to balance.
