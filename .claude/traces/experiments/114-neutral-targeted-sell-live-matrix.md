# 114 - Neutral Targeted SELL Live Matrix

Date: 2026-07-31
Status: DONE - player-facing integrity fallback

## Purpose

H116 identified H105 protected Druid work as the next completion-critical slice,
but that approval is still limited to the AI-agent files. Rather than retread
AI-only balance probes, this slice takes the H116 fallback: finish the Neutral
targeted SELL live-control matrix for Hoarder and Awakening.

This is player-facing integrity work. It improves the live playtest surface, but
it does not count as strategy-viability-floor progress.

## Scope

Covered visible-control SELL paths for:

- `ne_hoarder`: right-click SELL opens target selection, removes the source
  atomically, accepts the visible target overlay, transfers unit stacks, and
  grants tenure-based growth.
- `ne_awakening`: right-click SELL opens target selection, removes the source
  atomically, waits for a target choice, transfers an eligible upgrade, and
  returns modal ownership to BUILD.

While writing the Awakening coverage, a real transfer-integrity bug surfaced:
upgrade transfers appended upgrade dictionaries directly, so the receiver could
show the upgrade but miss its stat modifiers. The fix adds
`CardInstance.attach_upgrade_template(upgrade)` and routes live/headless transfer
effects through the same stat-application path used by normal upgrade purchase.

## Source State

- Branch: `main`
- HEAD before implementation: `702b0ec Record H105 post-H115 readiness`

## Files Changed

- `godot/core/card_instance.gd`
- `godot/scripts/game/game_manager.gd`
- `godot/sim/headless_runner.gd`
- `godot/tests/test_game_manager_live_smoke.gd`
- `godot/tests/test_neutral_system.gd`
- `godot/tests/test_upgrade_attach.gd`
- `Plans.md`
- `.claude/traces/experiments/114-neutral-targeted-sell-live-matrix.md`

## Verification

Initial focused live-smoke run found a separate GDScript error in the Awakening
flow:

```text
Trying to get a return value of a method that returns void.
```

That came from a void-return signal emission expression in
`_apply_awakening_transfer`. Replaced it with a normal guarded signal emission,
then reran the focused and broad suites.

PASS focused live smoke:

```text
test_game_manager_live_smoke.gd
21/21 tests
1502 assertions
```

PASS focused NeutralSystem:

```text
test_neutral_system.gd
58/58 tests
105 assertions
```

PASS focused HeadlessRunner:

```text
test_headless_runner.gd
15/15 tests
144 assertions
```

PASS focused upgrade attachment:

```text
test_upgrade_attach.gd
15/15 tests
47 assertions
```

PASS full GUT:

```text
57 scripts
1291/1291 tests
9466 assertions
```

PASS card spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

PASS whitespace guard:

```text
git diff --check
```

PASS protected H105 file check:

```text
git diff --name-only -- \
  godot/core/druid_system.gd \
  godot/tests/test_druid_system.gd \
  godot/tests/test_chain_engine.gd
```

No protected H105 files were changed.

## Boundary

This slice did not edit:

- `godot/core/druid_system.gd`
- `godot/tests/test_druid_system.gd`
- `godot/tests/test_chain_engine.gd`
- card YAML
- generated card DB files
- difficulty/economy values

The user's latest approval covers future edits to:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

Those files were not needed for H117 and remain outside this change. That
approval also remains separate from H105, which still requires explicit approval
for the protected Druid runtime/test file set.

## Decision

ADOPT as H117 player-facing integrity work.

Neutral targeted SELL flows are now covered through visible UI controls for
Masquerade, Hoarder, and Awakening, and transferred upgrades now apply their stat
modifiers consistently in live and headless paths.
