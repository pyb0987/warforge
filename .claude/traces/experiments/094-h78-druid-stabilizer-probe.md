# Experiment 094 - H78 Druid Stabilizer Probe

Date: 2026-07-30
Status: REJECTED - protected probe edits rolled back

## Goal

Run the H78 protected soft-Druid path-lag stabilizer probe after explicit user
approval to edit only:

- `godot/sim/ai_agent.gd`
- `godot/tests/test_ai_agent.gd`

The probe tested whether soft-Druid should allow conservative Druid/Neutral
stabilizer purchases while path-lagged when no current focus card is visible in
the shop.

## Baseline

Primary baseline: H94 same-seed soft-Druid 60-run sample.

- Report: `/private/tmp/warforge_h94_druid60.json`
- Traces: `/private/tmp/warforge_h94_druid60_traces`
- Summary: `/private/tmp/warforge_h94_druid60_summary.md`
- Result: 9/60 clears, avg final HP -4.23, avg rounds 11.07

## Probe Patch

Temporary protected edits:

- Added no-focus stabilizer thresholds to `AIAgent`.
- Built shop offer eval rows even when tracing is disabled so decision behavior
  does not depend on the tracer.
- Allowed high-score Druid or Neutral stabilizers only when no path focus offer
  is visible.
- Added focused AI tests for high/low value stabilizers and visible focus-offer
  preservation.

Focused pre-run verification passed:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

42/42 passed, 97 asserts
```

## Same-Seed Probe

Command:

```text
/usr/bin/env HOME=/private/tmp/warforge_godot_home_h78_stabilizer60 \
  godot --headless --log-file /private/tmp/warforge_h78_stabilizer60.log \
  --path godot/ -s tools/self_play_observer.gd -- \
  --runs=60 --strategies=soft_druid --difficulty=1 \
  --commander=gambler --talisman=flint \
  --seed=2026072901 \
  --out=/private/tmp/warforge_h78_stabilizer60.json \
  --trace-dir=/private/tmp/warforge_h78_stabilizer60_traces \
  --quiet-progress=true
```

Output artifacts:

- Report: `/private/tmp/warforge_h78_stabilizer60.json`
- Summary: `/private/tmp/warforge_h78_stabilizer60_summary.md`
- Traces: `/private/tmp/warforge_h78_stabilizer60_traces`
- Analyzer comparison:
  `/private/tmp/warforge_h78_stabilizer60_druid_vs_h94.txt`

Result:

- Clears: 9/60 -> 8/60, delta -1
- Win rate: 15.0% -> 13.3%, delta -1.7pp
- Avg final HP: -4.23 -> -4.42, delta -0.18
- Avg rounds: 11.07 -> 11.03, delta -0.03
- Completion readiness: `needs_attention`
- Summary alert: `low_overall_clear_rate`

## Diagnostic Read

The patch improved the narrow hold symptom:

- Path-lag holds: 255 -> 121, delta -134
- Hold runs: 50 -> 41, delta -9
- No-focus hold rate: 98.4% -> 90.9%, delta -7.5pp
- Actionable no-focus loss runs: 37 -> 21, delta -16
- Affordable focus holds: 1 -> 1, delta +0
- `active_too_late`: delta -4

But it did not convert into the actual strategy floor:

- Clears fell by one run, triggering the predeclared reject rule.
- H74 comparison screen verdict: `REJECT_FLAT_OR_NOISY`.
- R9-R11 focus-active WR moved only 34.6% -> 35.2%.
- Active-loss survivor margin did not improve: ally 0.0 -> 0.0, enemy 13.8 -> 13.9.
- `no_payoff_seen` worsened by +5.
- The analyzer next signal moved toward board activation/promotion and Spore
  pressure conversion, not more path-lag loosening.

## Advisory Multi-Review

| Critic | Score | Verdict | Key Finding |
|--------|-------|---------|-------------|
| Gate correctness | 9/10 | REJECT | Clears fell and `REJECT_FLAT_OR_NOISY` independently trigger the predeclared reject screen. |
| Gameplay diagnosis | 5/10 | MIXED | The probe reduced dead holding, but did not improve survival, focus timing, or active battle margins. |
| Scope and rollback | 9/10 | ROLLBACK | Keeping failed protected simulator edits would contaminate the next baseline. |

Integrated recommendation: reject H78 as-is, keep the diagnostic lesson, and
roll back the two protected probe edits.

## Rollback

Rollback command:

```text
git restore godot/sim/ai_agent.gd godot/tests/test_ai_agent.gd
```

Post-rollback verification:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit

39/39 passed, 94 asserts
```

Boundary check:

- `git status --short -- godot/sim/ai_agent.gd godot/tests/test_ai_agent.gd`
  produced no output.
- `git diff -- godot/sim/ai_agent.gd godot/tests/test_ai_agent.gd`
  produced no output.

## Decision

REJECT. H78 was executed, failed its adoption screen, and left no gameplay code
or protected simulator/test edits in the final working tree.

## Next

Do not retry the same no-focus stabilizer fallback as-is. The next Druid repair
should be selected from the H78/H94 diagnostics, with priority on:

- board activation/promotion after payoff purchase;
- Spore pressure conversion, especially debuff scaling/caps in active R9-R11
  losses;
- preserving a clean baseline before any further protected simulator or
  gameplay-value edits.
