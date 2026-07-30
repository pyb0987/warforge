# 088 - Raider Carried Win-Count Coverage

Date: 2026-07-30

## Goal

Close the already-started H92 run by adding live visible-control coverage for
Raider's real 3-win reward flow without editing balance, combat, economy, card
data, or protected simulator files.

## Context

H91 extended the terminal visible-control playthrough to Smith's start
free-upgrade flow. Raider was the next unprotected identity because its
distinctive reward opens a free common-upgrade selection after the commander win
counter reaches three.

Earlier H92 attempts tried to let the simple visible-control player produce the
full Raider cadence from zero with Raider/Flint and Raider/War Drum. Those runs
reached terminal states but did not produce a clean full natural 3-win cadence.
The adopted coverage therefore carries Raider's existing local `win_count` at 2
and lets the next real win trigger the actual reward plumbing.

## Change

Added `test_live_raider_visible_control_playthrough_resolves_carried_win_count_upgrade`
to `test_game_manager_live_smoke.gd`.

The test:

- explicitly unlocks Raider in the isolated smoke profile;
- selects Raider through the commander popup;
- selects Flint through the talisman popup;
- carries Raider's local `win_count` at 2;
- plays real build and battle surfaces through visible controls;
- observes pending upgrade source `raider_win_streak`;
- verifies the visible free-upgrade target flow attaches an upgrade;
- continues through real battles to the real terminal overlay.

The visible-control helper now accepts an optional commander-state setup
dictionary. Existing callers still use the default empty setup.

## Evidence

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
17/17 passed.
1219 asserts.
```

Observed Raider reward summary from the full-suite log:

```text
Commander selected: Raider
Talisman selected: Flint
Free upgrade source applied: C5 (raider_win_streak)
Raider 3-win reward applied
Terminal overlay reached after GAME OVER at round 8
```

Card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result: exited 0 with no output.

Full GUT:

```text
/usr/bin/env HOME=/private/tmp/warforge_h92_fullgut_home godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result:

```text
Scripts              57
Tests              1281
Passing Tests      1281
Asserts            9169
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

Raider's 3-win reward plumbing now has live visible-control terminal coverage
from a carried two-win counter. This is intentionally narrower than proving the
automated visible-control player can generate three Raider wins from zero.

## Protected Boundary

No `godot/sim/**` files were edited. H78 remains gated on explicit protected
simulator approval.

## Next

Pause here per user request. On resume, choose a new slice from this boundary:
fully natural Raider-from-zero coverage, another distinctive commander/talisman
live path, or explicit approval for protected H78 simulator work.
