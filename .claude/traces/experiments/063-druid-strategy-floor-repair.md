# 063 - Druid Strategy Floor Repair

Date: 2026-07-29
Status: DONE - rejected tested gameplay variants; no H67 behavior adopted

## Objective

H66 identified `soft_druid` as the weakest D1 self-play lane after the player-facing loop work:
0/5 clears in the 35-run all-strategy matrix, with recurring `combat_conversion_failure`,
`path_lag_hold_pressure`, and `payoff_no_debuff_conversion` buckets.

The H67 goal was to test narrow Druid-local AI repairs without touching difficulty values or card
numbers, and to keep only a variant that improved actual outcomes on a same-seed focused gate.

## Review Synthesis

Multi-review used three independent critics before implementation:

- Gameplay/AI critic: prefer combat conversion valuation/activation; only relax path-lag holds
  after payoff ownership if the card is clearly useful. Avoid more card buffs for now.
- Measurement critic: refresh a 30-run same-seed baseline; require at least +3/30 clears and
  meaningful HP/bucket movement before adoption.
- Frame critic: treat this as a weak-strategy-floor slice, not a precommitted Druid buff. Confirm
  Steampunk/economy weak lanes are distinct before focusing Druid.

Quick cross-lane check supported the Druid-local focus: `soft_steampunk` and `economy` were also
weak in small samples, but their buckets were not the same Druid path-lag/payoff-conversion surface.

## Baseline

Command:

```bash
HOME=/private/tmp/warforge_godot_home_h67_druid_base godot --headless --log-file /private/tmp/warforge_h67_druid_base_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h67_druid_base_30.json --trace-dir=/private/tmp/warforge_h67_druid_base_30_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h67_druid_base_30_traces --strategy=soft_druid --druid-loss-buckets
```

Result:

- Clears: 4/30 (13.3%)
- Avg final HP: -4.20
- Avg rounds: 11.07
- Loss buckets: `combat_conversion_failure` 10, `path_lag_hold_pressure` 16,
  `payoff_no_debuff_conversion` 7, `payoff_acquisition_lag` 8,
  `owned_not_active_gap` 3, `tier_access_lag` 4
- Payoff funnel in losses: offered 21, affordable 19, bought 18

## Variants

### A - Druid Payoff Valuation/Activation

Tested extra scoring/board valuation for Druid payoff conversion.

Result:

- Clears: 2/30
- Avg final HP: -7.47
- Buckets worsened: `combat_conversion_failure` 13, `path_lag_hold_pressure` 17

Decision: REJECT. Mechanism confidence was not enough; actual survival regressed sharply.

### B - Druid-Only Post-Payoff Support Exception

Allowed Druid support cards after a shared payoff was already owned, while still holding generic filler.

Result:

- Clears: 4/30
- Avg final HP: -3.37
- Buckets: `combat_conversion_failure` 11, `path_lag_hold_pressure` 16,
  `payoff_no_debuff_conversion` 6

Decision: REJECT. HP improved slightly, but clears were flat and this missed the agreed adoption
threshold.

### C - Neutral Post-Payoff Support Exception

Extended B to allow selected neutral support cards after shared payoff ownership.

Result:

- Clears: 4/30
- Avg final HP: -4.03
- Path-lag holds fell to 122, but outcome was flat and weaker than B.

Decision: REJECT. Reducing one diagnostic counter was a false green.

### D - R3 Druid Identity Commitment

Removed C, kept B as the local base, and tested Druid committing at R3 instead of R4.

Command:

```bash
HOME=/private/tmp/warforge_godot_home_h67_druid_r3_identity godot --headless --log-file /private/tmp/warforge_h67_druid_r3_identity_30.log --path godot/ -s tools/self_play_observer.gd -- --runs=30 --strategies=soft_druid --difficulty=1 --commander=gambler --talisman=flint --seed=2026072901 --out=/private/tmp/warforge_h67_druid_r3_identity_30.json --trace-dir=/private/tmp/warforge_h67_druid_r3_identity_30_traces --quiet-progress=true
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h67_druid_r3_identity_30_traces --strategy=soft_druid --druid-loss-buckets
```

Result:

- Clears: 3/30
- Avg final HP: -3.93
- Avg rounds: 10.93
- Enemy debuffs seen: 36.7% of runs
- Loss buckets: `combat_conversion_failure` 10, `payoff_no_debuff_conversion` 9,
  `path_lag_hold_pressure` 14, `payoff_acquisition_lag` 8, `low_druid_board_ratio` 5

Decision: REJECT. It improved theme ratio and first-path timing only slightly, but worsened clear
rate and payoff/debuff conversion.

## Final Decision

No H67 gameplay behavior is adopted. The neutral-support and R3-identity changes were removed, and
the focused AI suite passes after revert:

```bash
HOME=/private/tmp/warforge_godot_home_h67_ai_agent_post_revert godot --headless --log-file /private/tmp/warforge_h67_ai_agent_post_revert.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
```

PASS: `test_ai_agent.gd` 39/39.

## Next Slice

The next completion-oriented slice should stop testing purchase/commit timing by itself. Evidence
now says Druid often reaches some intended pieces but still fails the survival curve. The next
promising direction is a battle-frame conversion audit: inspect active Druid payoff rounds, tree
counts, enemy debuff applications, ally/enemy survivors, and why payoff-active rounds still die.

Do not repeat these rejected variants without a stronger evaluator:

- Post-payoff neutral support allowance
- Earlier Druid R3 commitment
- Generic payoff valuation/promotion that increases visibility but lowers HP
