# Episode 040: Growth-chain readable pacing

Date: 2026-07-27

## Context

The latest manual play feedback called out that growth-chain feedback appears
but advances too quickly to inspect. A related UI concern was that transient
messages can become stale or compete with active decision modals.

H43 already quieted tutorial hints during target/reward decisions, so H44 could
make the chain itself more readable without changing card values or combat
balance.

## Multi-Review

Advisory reviewers converged on a hybrid approach:

- Use bounded dynamic timing based on the number of chain events instead of a
  fixed short pause.
- Keep a persistent last-chain history into the next BUILD phase, separate from
  transient link/floating-label visuals.
- Preserve expert flow with an explicit skip path, and guard against timer
  races so skip cannot advance phases twice.

## Change

`ChainVisual` now distinguishes three surfaces:

- transient links/floating labels, cleared every chain phase;
- a compact six-line live event log for the current chain;
- a capped 30-line last-completed chain history that survives normal visual
  clearing and can be explicitly cleared on run setup.

`GameManager` now computes chain-feedback duration from:

```text
base delay + per-event delay, capped by max delay
```

The default is 1.6s base, +0.25s per extra event, capped at 3.2s. Pressing
Space during CHAIN calls `skip_chain_feedback()`, which advances to BATTLE once
and ignores the original timer when it later wakes.

`BuildPhase` now exposes a compact `LAST CHAIN` panel in BUILD, populated from
the just-completed chain. It hides while target selection or merge reward choice
UI is visible, then returns when the modal closes.

## Verification

Focused chain visual suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h44_chain_visual.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit
  8/8 passed, 34 asserts
```

Focused BuildPhase tutorial/history suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h44_build_phase_tutorial.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit
  9/9 passed, 25 asserts
```

Live scene smoke:

```text
PASS godot --headless --log-file /private/tmp/warforge_h44_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  11/11 passed, 301 asserts
```

Full suite:

```text
PASS git diff --check
PASS godot --headless --log-file /private/tmp/warforge_h44_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1229/1229 passed, 7873 asserts
```

## Decision

Keep H44. It directly addresses the playtest readability complaint without
slowing every chain unboundedly, and it gives players a reviewable last-chain
summary after battle transition.

## Carry-Over

H45 should add screenshot/report coverage for the actual chain pause and
last-chain BUILD panel. H44 has semantic coverage, but the visible panel should
be part of the GUI evidence pipeline before further UI polish.
