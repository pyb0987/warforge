# 086 — Initial Commander Natural-Run Coverage

Date: 2026-07-30

## Goal

Reduce the risk that the only natural visible-control terminal run is tied to a
single commander identity.

## Context

H85 introduced a fresh-profile visible-control playthrough acceptance smoke, but
it only covered Gambler/Flint. H89 made the resulting R8 defeat more actionable
for the player. The next unprotected completion step is to prove the same
player-control path works for more than one initially available identity before
moving to locked identities or protected simulator work.

## Change

The visible-control terminal playthrough helper in
`test_game_manager_live_smoke.gd` is now parameterized by commander and talisman.

Coverage now includes:

- Gambler/Flint, preserving the original acceptance path.
- Breeder/Flint, covering the second initially unlocked commander.

Both paths still rely on real run-start selection, visible controls, real
battles, and the actual terminal overlay. The tests do not force battle results,
seed run stats, inject generated unlocks, or edit balance.

## Evidence

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
15/15 passed.
1043 asserts.
```

Observed natural terminal outcomes:

```text
Gambler/Flint: GAME OVER at round 8
Breeder/Flint: GAME OVER at round 8
```

Card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result: exited 0 with no output.

Full GUT:

```text
/usr/bin/env HOME=/private/tmp/warforge_h90_fullgut_home godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result:

```text
Scripts              57
Tests              1279
Passing Tests      1279
Asserts            8990
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

## Log Notes

Full GUT printed the same macOS certificate probe line at startup and expected
negative-path diagnostics from invalid card and revive-scope tests.

## Decision

ADOPT.

Both initially unlocked commanders now have natural visible-control terminal
coverage. This is a stronger player-loop acceptance anchor than the previous
single-identity path.

## Protected Boundary

No `godot/sim/**` files were edited. H78 remains gated on explicit protected
simulator approval.

## Next

Checkpoint the current H79-H90 stack soon. After that, either extend natural-run
coverage to unlocked identities through explicit profile setup, or request
explicit approval for the protected H78 Druid probe.
