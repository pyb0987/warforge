# Episode 028: Live chain event readability smoke

## Context

H31 covered the first R4 boss reward modal transition. The next likely live
readability risk was the growth-chain output itself:

- H30 proved the chain overlay becomes visible before battle.
- Existing live smoke did not prove that actual chain events are readable in the
  main scene.
- `ChainVisual` showed enhancement events as `+ATK%`, even though chain
  enhancement actions may affect ATK, HP, or both depending on the card.

## Change

Updated `ChainVisual` display text:

- `enhance` action now renders as `+Stats` instead of `+ATK%`;
- layer labels now use readable names such as `Unit Added / Manufacture` and
  `Enhanced / Upgrade` instead of lower-case internal tokens.

Added `test_live_chain_event_history_is_readable_before_battle` to the live
scene smoke:

- starts the real main scene;
- places `sp_assembly` beside `sp_workshop`;
- presses build complete;
- asserts the chain phase is visible;
- asserts the readability panel opens;
- asserts the event history includes the source and target card names,
  `+Unit`, `+Stats`, and `Complete:`;
- drains the short chain delay and confirms combat starts.

## Verification

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h32_chain_visual.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit
  6/6

PASS godot --headless --log-file /private/tmp/warforge_h32_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  6/6

PASS godot --headless --log-file /private/tmp/warforge_h32_chain_engine.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit
  20/20

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h32_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1213/1213
```

## Decision

Keep the H32 change.

Reason:

- It improves a player-facing feedback surface without changing mechanics.
- The live smoke now exercises a real chain with both spawn and enhancement
  output.
- Focused and full GUT verification pass.

Carry-over:

- Continue live/manual UX smoke for the next player-facing gap.
- Candidate next area: post-battle reward/result pacing around the transition
  from chain visibility into combat visibility, preferably checked with a
  screenshot or browser/tool-assisted visual run when practical.
