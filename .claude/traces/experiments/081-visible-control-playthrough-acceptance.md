# 081 — Visible-Control Playthrough Acceptance

Date: 2026-07-29

## Goal

Challenge the scripted live-report false-green risk after H84 with one
fresh-profile live-scene playthrough that reaches a terminal overlay through
visible control paths and real battle outcomes.

## Context

H84 proved the Raider 3-win reward flow and the expanded identity matrix, but
those reports still use state injection to reach specific reward and terminal
cases. The H84 multi-review split three ways:

- Player-completion critic: run a non-scripted live playability acceptance pass.
- Observability critic: package the expanded identity matrix as a named preset.
- Scope-safety critic: avoid growing the stack before checkpointing H79-H84.

This slice followed the player-completion recommendation while keeping the
change unprotected and narrow.

## Change

Added `test_live_visible_control_playthrough_reaches_terminal_overlay` to
`godot/tests/test_game_manager_live_smoke.gd`.

The acceptance test:

- resets the profile and starts the main scene;
- selects Gambler and Flint via the existing run-start UI;
- buys shop cards by emitting left-click input on visible shop slots;
- moves bench cards to the field through the card visual drop path;
- optionally buys and attaches a visible upgrade through target selection;
- resolves merge reward, target, theme, and boss reward modals through visible
  choices;
- presses BUILD COMPLETE and skips readable chain feedback with Space;
- lets real battles and settlement drive progress;
- requires the real game-over popup and saved meta result at the end.

The test does not seed cards, rounds, HP, gold, or battle results during the
acceptance run.

## Evidence

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
14/14 passed.
947 asserts.
```

Observed H85 acceptance path:

- Bought visible shop cards across R1-R7.
- Drag/dropped bench cards onto FIELD.
- Bought and attached visible upgrades.
- Selected a merge reward popup.
- Selected an R4 boss reward popup.
- Let real battles resolve naturally.
- Reached real game-over overlay after natural R8 defeat.

## Protected Boundary

No `godot/sim/**` files were edited.

## Decision

ADOPT.

The test adds a real-control acceptance guard without changing balance or
runtime gameplay. It reduces the risk that scripted report coverage hides a
modal dead-end or missing terminal transition in ordinary play.

## Next

Checkpoint or explicitly triage the dirty H79-H85 stack before growing another
feature slice. After that, the next small unprotected workflow slice is a named
expanded identity matrix preset; the main protected completion blocker remains
H78 until simulator edit approval is explicit.
