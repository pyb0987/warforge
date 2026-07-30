# 090 - H78 No-Edit Druid Preflight

Date: 2026-07-30

## Goal

Advance the highest-impact known gameplay-completion candidate, H78 Druid
strategy-floor viability, without editing protected `godot/sim/**` files before
explicit approval.

## Context

H93 completed the best unprotected live-control slice. Advisory review still
identified H78 as the strongest player-impact next move, because the Druid lane
remains weak and prior H77 evidence pointed to no-focus `path_lag_hold` behavior
through the R9-R12 lethal window.

The H78 approval packet remains:

```text
.claude/traces/experiments/074-druid-protected-ai-probe-approval-packet.md
```

It asks for approval to edit:

```text
godot/sim/ai_agent.gd
godot/tests/test_ai_agent.gd
```

## Change

No gameplay, simulator, UI, card, economy, difficulty, or generated files were
changed.

This slice refreshed the preflight evidence and created a fresh current
soft-Druid baseline artifact:

```text
/private/tmp/warforge_h94_druid60.json
/private/tmp/warforge_h94_druid60_summary.md
/private/tmp/warforge_h94_druid60_traces
```

## Evidence

Focused AI tests:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
```

Result:

```text
39/39 passed.
94 asserts.
```

H78 packet pre-probe analyzer on existing H75 vs H71 traces:

```text
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-run-phase --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
```

Key result:

```text
H75: 10/60 clears, avg HP -3.45.
R8-R12 path-lag holds: 265.
No-focus holds: 260/265 (98.1%).
Affordable-focus holds: 1.
Gate: GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD.
Comparison screen: WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT.
```

Fresh current no-edit baseline:

```text
/usr/bin/env HOME=/private/tmp/warforge_h94_druid60_home godot --headless --log-file /private/tmp/warforge_h94_druid60.log --path godot/ -s tools/self_play_observer.gd -- --runs=60 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h94_druid60.json --trace-dir=/private/tmp/warforge_h94_druid60_traces --quiet-progress=true
```

Key result from JSON and summary:

```text
60 runs.
9/60 clears (15.0%).
Avg final HP: -4.23.
Avg rounds played: 11.07.
Completion readiness: needs_attention.
Top risk: low_overall_clear_rate.
```

Fresh current Druid analyzer:

```text
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h94_druid60_traces --strategy=soft_druid --druid-active-ledger --druid-run-phase --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
```

Key result:

```text
R9-R11 focus-active frames: 81.
R9-R11 focus-active WR: 34.6%.
Active-loss survivor margin: ally 0.0, enemy 13.8.
R8-R12 path-lag holds: 255.
No-focus holds: 251/255 (98.4%).
Affordable-focus holds: 1.
Actionable no-focus loss runs: 37.
Gate: GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD.
Same-seed comparison vs H71: unchanged baseline.
```

Card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result: exited 0 with no output.

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

ADOPT as a readiness artifact.

H78 remains current and well-scoped. The fresh no-edit baseline reproduces the
same-seed H71 behavior exactly on the comparison screen, while the path-lag
audit still points at the no-focus stabilizer policy probe.

## Protected Boundary

No `godot/sim/**` files were edited.

## Next

Ask for explicit approval before editing protected `godot/sim/ai_agent.gd` for
H78. If approved, implement the narrow no-focus stabilizer probe exactly against
the H78 packet, then compare against the fresh H94 baseline and the existing
H71/H75 artifacts.
