# 089 - Strategist Visible SWAP Coverage

Date: 2026-07-30

## Goal

Continue game-completion work after H92 without touching protected simulator
files by adding live visible-control coverage for a distinctive active
commander ability.

## Decision Review

Advisory multi-review was used because the next-slice choice mattered.

Result: `FALLBACK_NONINDEPENDENT`, advisory only.

- Player-completion critic: preferred H78 Druid path-lag work because weak
  Druid strategy-floor viability is still a stronger gameplay-completion
  blocker than more identity smoke coverage.
- Frame-challenge critic: also preferred H78 and warned that green identity
  smoke can falsely look like completion while a whole archetype remains weak.
- Scope/verification critic: vetoed protected `godot/sim/**` edits without
  explicit approval and recommended a narrow unprotected Strategist/War Drum
  live path that must assert the distinctive SWAP behavior.

Decision: keep H78 gated on explicit protected simulator approval, and adopt H93
as the best autonomous unprotected progress slice.

## Change

Added `test_live_strategist_visible_control_playthrough_resolves_swap` to
`test_game_manager_live_smoke.gd`.

The test:

- explicitly unlocks Strategist and War Drum in the isolated smoke profile;
- selects Strategist through the commander popup;
- selects War Drum through the talisman popup;
- plays real build controls until at least two field cards are present;
- presses the visible SWAP button;
- clicks two visible field card controls;
- verifies the board card references exchange slots;
- verifies `hero_used` becomes true;
- verifies the SWAP button and identity HUD show the used state;
- continues through real chains, battles, boss rewards, and the real terminal
  overlay.

The natural playthrough helper now accepts optional play options so
identity-specific visible-control assertions can be added without affecting the
default Gambler/Breeder/Smith/Raider paths.

## Evidence

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
18/18 passed.
1327 asserts.
```

Focused Strategist UI state machine:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_strategist_swap.gd -glog=1 -gexit
```

Result:

```text
6/6 passed.
23 asserts.
```

Focused talisman coverage:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman.gd -glog=1 -gexit
```

Result:

```text
38/38 passed.
108 asserts.
```

Card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result: exited 0 with no output.

Full GUT:

```text
/usr/bin/env HOME=/private/tmp/warforge_h93_fullgut_home godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result:

```text
Scripts              57
Tests              1282
Passing Tests      1282
Asserts            9271
---- All tests passed! ----
```

Whitespace/conflict guard:

```text
git diff --check
```

Result: exited 0.

Protected simulator boundary:

```text
git status --short -- godot/sim
```

Result: no output.

## Decision

ADOPT.

Strategist's active SWAP is now covered in the same live visible-control
terminal acceptance path as the other recent commander identity checks.

## Protected Boundary

No `godot/sim/**` files were edited. H78 remains gated on explicit protected
simulator approval.

## Next

Checkpoint H91-H93 soon. After that, either ask explicit approval for H78
protected Druid simulator work or continue with another unprotected
player-facing slice if approval is not available.
