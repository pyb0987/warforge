# 112 - Live Masquerade Sell Flow

Date: 2026-07-31
Status: DONE - live-scene player path coverage

## Purpose

Close a player-facing observability gap around `ne_masquerade` SELL. The
NeutralSystem runtime already returned `needs_target_select`, and
`game_manager.gd` already routed that through the live target overlay and
theme-choice popup, but the active smoke suite did not prove the visible-control
path end to end. A stale comment in `neutral_system.gd` also still said the UI
was missing.

This is not an H105 Druid strategy-viability probe. It does not edit protected
Druid runtime/test files or any card data.

## Change

- Added a live smoke test that:
  - puts `dr_cradle` and `ne_masquerade` on the field,
  - right-clicks Masquerade through the visible card control,
  - verifies target selection opens first,
  - selects the target through the public target overlay,
  - verifies the theme-choice popup opens with exactly three choices for star 1,
  - selects a non-current theme through the visible popup button,
  - verifies the target card receives that chosen theme,
  - verifies modal ownership returns to BUILD.
- Added test helpers for visible right-click emission, theme-choice lookup by
  button text, and theme-label mapping.
- Replaced the stale Masquerade comment with an accurate note: live UI handles
  player choice, while the target/theme fallback stays for sim/headless
  determinism and UI metadata.

## Verification

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

- PASS `test_game_manager_live_smoke.gd`
- 19/19 tests
- 1390 assertions

Focused NeutralSystem:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_neutral_system.gd -glog=1 -gexit
```

Result:

- PASS `test_neutral_system.gd`
- 57/57 tests
- 103 assertions

Card spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result:

- PASS

Full Godot suite:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ -glog=1 -gexit
```

Result:

- PASS
- 57 scripts
- 1287/1287 tests
- 9342 assertions

Whitespace guard:

```text
git diff --check
```

Result:

- PASS

## Boundary

Gameplay/code edits:

- `godot/tests/test_game_manager_live_smoke.gd`
- `godot/core/neutral_system.gd`

Record-only files:

- `Plans.md`
- `.claude/traces/experiments/112-live-masquerade-sell-flow.md`

Not touched:

- Card YAML data
- Generated `godot/core/data/card_db.gd`
- Difficulty or economy files
- AI simulator files
- Protected H105 Druid runtime/test files:
  - `godot/core/druid_system.gd`
  - `godot/tests/test_druid_system.gd`
  - `godot/tests/test_chain_engine.gd`

## Decision

ADOPT.

The player-facing Masquerade SELL flow is now covered by an end-to-end live
smoke test. This removes an outdated TODO as a source of future confusion while
keeping H105 untouched and still gated on explicit protected-file approval.
