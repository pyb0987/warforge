# Experiment 097 - H100 No-Edit Readiness

Date: 2026-07-30
Status: READY - H100 still awaits fresh protected-edit approval

## Purpose

Verify, without editing protected files, that the H99 approval packet for the
H100 Druid duplicate-focus activation probe still matches the current code and
current evidence.

This is a readiness check only. It does not approve, implement, or adopt any
gameplay behavior.

## Current Boundary

Fresh approval is still required before editing:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

No approval currently carries forward from H78. Do not edit other protected
`godot/sim/**` files, card YAML, generated card DB, combat/runtime systems,
difficulty values, economy values, or progression thresholds for H100.

## Packet-To-Code Check

Read-only checks against the current repo:

- `_find_path_focus_replacement()` still skips current focus cards before
  duplicate-active focus copies can be considered.
- `_should_skip_path_focus_swap()` still allows duplicate active focus copies
  by returning false when `_active_card_count(state, outgoing_id) > 1`.
- `_path_focus_activation_gap()` still uses the payoff/capstone gap value
  `42.0`.
- Existing `test_ai_agent.gd` already has nearby Druid path-focus promotion
  coverage that the H100 focused tests can extend.

Command output:

```text
finder_skips_current_cards: True
swap_allows_duplicate_focus: True
path_focus_gap_42: True
path_focus_promotion_test_exists: True
```

## Baseline Tests

Current unmodified focused AI test baseline:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

39/39 passed, 94 asserts
```

Current Python analyzer baseline:

```text
python3 -m unittest scripts.tests.test_analyze_ai_trace \
  scripts.tests.test_summarize_self_play_report -q

Ran 24 tests in 0.005s
OK
```

Protected/tuning boundary check produced no output for:

- `godot/sim`
- `godot/tests/test_ai_agent.gd`
- `data/cards`
- `godot/scripts/generated`
- `godot/scripts/data/difficulty_config.gd`

## No-Edit H94 Preflight

Command:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h94_druid60_traces \
  --strategy=soft_druid \
  --druid-activation-audit \
  --druid-path-lag-audit \
  --druid-run-phase \
  > /private/tmp/warforge_h100_noedit_h94_preflight.txt
```

Key read:

- H94 remains 9/60 clears, avg HP -4.2, avg rounds 11.1.
- Run-phase still says focus activation often happens in the lethal window:
  `active_too_late` 16/60, dead within one round after activation 18/32
  active-loss runs.
- Activation audit still shows a real bench/promotion tail:
  - 42/60 payoff buy runs;
  - 63 bought payoff copies;
  - 46 active after buy;
  - 17 never active after buy;
  - 29 inactive frames from 20 runs;
  - 23 bench gaps;
  - 19 no-attempt bench gaps;
  - 19 promotion skips;
  - `druid_world_tree` carries 20 inactive frames, 16 bench gaps, and 16
    promotion skips.
- Path-lag audit still emits `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD` on
  H94, but H78 already tested and rejected that exact direction. Do not retry
  the no-focus stabilizer fallback as-is.

## Decision

H100 remains the next strategy-floor step if protected edits are approved:
implement the H99 duplicate-current-focus activation probe, then judge it by
the packet's same-seed outcome and activation gates.

If approval is not granted, do not claim M1 strategy viability progress from
more unprotected diagnostics.
