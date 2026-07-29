# H66 - Current Completion Readiness Refresh

Date: 2026-07-29
Status: ADOPTED

## Objective

Refresh whole-run completion evidence after the H58-H65 live-readability arc.
The goal was not to tune difficulty or add another local UI surface yet; it was
to determine the next completion blocker from current evidence and avoid both
stale sim conclusions and green-but-narrow live UI smoke confidence.

## Decision

Advisory multi-review:

- Player/product completion critic: choose current completion evidence refresh.
  The H58-H65 arc improved first-run clarity, but did not prove the 15-round
  loop currently completes well across strategies and reward milestones.
- Measurement critic: choose the same slice. The strongest false-green risk is
  live UI screenshots passing while clear rates, reward reach, strategy floors,
  or unlock pressure are broken.
- Frame-challenge critic: prefer a directly playable roadmap/progression rail,
  warning that more measurement can become planning anxiety.

I adopted the evidence refresh, but changed its shape to answer the frame
challenge: H66 must produce a ranked completion-readiness verdict and a next
slice recommendation, not just another metrics dump.

Deferred:

- Full R1-R15 roadmap/progression rail, unless completion evidence shows
  whole-run orientation is the next blocker.
- Direct difficulty tuning, unless fresh evidence shows a difficulty defect.
- Combat causality/log work, unless play/evidence shows battle readability is
  now the binding blocker.

## Implementation

- `godot/tools/self_play_observer_logic.gd`
  - Added `completion_readiness` to the self-play JSON summary.
  - Ranks top completion risks such as weak strategy floors, low clear rate,
    boss reward application gaps, early/mid/late survival walls, unlock burst
    pressure, and partial observer coverage.
  - Produces `status`, sample strength, `top_risks`, and
    `recommended_next_slice`.
  - Fixed a false-positive oracle: boss milestone reward checks now distinguish
    raw milestone reach from reward eligibility after winning that boss round.
    Reward parity uses `eligible_runs` and `reward_rate_of_eligible`.

- `scripts/summarize_self_play_report.py`
  - Validates `completion_readiness` as a required section.
  - Renders the readiness verdict, sample size, ranked risks, and
    eligible-vs-applied boss milestone evidence.

- Tests and docs:
  - `godot/tests/test_self_play_observer.gd`
  - `scripts/tests/test_summarize_self_play_report.py`
  - `docs/tools/self-play-observer.md`

## Current Evidence

Command:
`HOME=/private/tmp/warforge_godot_home_h66_selfplay2 godot --headless --log-file /private/tmp/warforge_selfplay_h66_2.log --path godot/ -s tools/self_play_observer.gd -- --runs=5 --strategies=all --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_selfplay_h66_2.json --trace-dir=/private/tmp/warforge_selfplay_h66_traces2 --quiet-progress=true`

Result:

- Overall: 17/35 clears, 48.6% clear rate, average round 12.97, average final
  HP 10.0.
- Strategy split:
  - `soft_predator`: 5/5 clears, avg R15.0.
  - `adaptive`: 4/5 clears, avg R15.0.
  - `aggressive`: 4/5 clears, avg R14.6.
  - `soft_military`: 2/5 clears, avg R11.6.
  - `economy`: 1/5 clears, avg R11.4.
  - `soft_steampunk`: 1/5 clears, avg R12.0.
  - `soft_druid`: 0/5 clears, avg R11.2.
- Boss milestones after eligibility correction:
  - R4 reached 35, eligible 33, reward applied 33, reward/eligible 100%.
  - R8 reached 34, eligible 25, reward applied 25, reward/eligible 100%.
  - R12 reached 25, eligible 21, reward applied 21, reward/eligible 100%.
- Completion readiness:
  - Status: `needs_attention`.
  - Top risk: `weak_strategy_floor` - `soft_druid 0/5 clears, avg R11.2`.
  - Secondary risk: `unlock_burst_pressure` - largest run projects 11 raw
    unlocks, with up to 8 deferred by the 3-unlock reveal cap.
  - Recommended next slice: repair the worst strategy lane only after
    inspecting trace buckets.

Trace diagnostics:

- `soft_druid --druid-loss-buckets`
  - 0/5 clears, avg rounds 11.2.
  - Detected paths in all runs: 3 `druid_world_tree`, 2 `druid_garden`.
  - Loss buckets: `combat_conversion_failure` 3, `path_lag_hold_pressure` 3,
    `payoff_no_debuff_conversion` 2, `tier_access_lag` 1,
    `owned_not_active_gap` 1.
  - Payoffs were offered/affordable/bought in 5/5 losses, so the immediate
    problem is not basic payoff access.

- `soft_steampunk --steampunk-loss-buckets`
  - 1/5 clears, avg rounds 12.0.
  - Loss buckets still show tier/payoff acquisition and branch-mix pressure,
    but it is not the only zero-clear lane in the current sample.

## Verification

PASS `python3 -m py_compile scripts/summarize_self_play_report.py`

PASS `python3 -m unittest scripts.tests.test_summarize_self_play_report`
- 3 tests passed.

PASS focused observer GUT:
`HOME=/private/tmp/warforge_godot_home_h66_observer2 godot --headless --log-file /private/tmp/warforge_selfplay_observer_h66_2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit`
- 9/9 passed.
- 72 asserts.

PASS self-play summary:
`python3 scripts/summarize_self_play_report.py --report=/private/tmp/warforge_selfplay_h66_2.json --out=/private/tmp/warforge_selfplay_h66_2_summary.md`
- Verdict PASS.
- Includes `Completion Readiness`, `weak_strategy_floor`, and boss
  `reward/eligible 100.0%` lines.

PASS trace diagnostics:
- `python3 scripts/analyze_ai_trace.py /private/tmp/warforge_selfplay_h66_traces2 --strategy=soft_druid --druid-loss-buckets`
- `python3 scripts/analyze_ai_trace.py /private/tmp/warforge_selfplay_h66_traces2 --strategy=soft_steampunk --steampunk-loss-buckets`

PASS `python3 scripts/lint_card_spawn.py`

PASS `python3 -m unittest discover -s scripts/tests`
- 109 tests passed.

PASS full GUT:
`HOME=/private/tmp/warforge_godot_home_h66_full godot --headless --log-file /private/tmp/warforge_full_gut_h66.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
- 57 scripts.
- 1265/1265 tests passed.
- 8549 asserts.

## Outcome

ADOPTED. H66 refreshes completion evidence and makes the observer
decision-aware. The current best next completion slice is a Druid strategy-floor
investigation/repair using trace buckets, not a roadmap rail or broad
difficulty tuning.
