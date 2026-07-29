# Experiment 073 - Druid Path-Lag Decision Audit

Date: 2026-07-29
Status: DONE - behavior-neutral analyzer adopted; protected AI probe recommended

## Question

H76 showed that Druid, especially Garden, often activates payoff/focus in a
lethal window. Before asking to edit protected AI policy in `godot/sim/**`, can
existing traces prove a repeated decision-class defect rather than only outcome
correlation?

## Review Synthesis

Used multi-review because H77 decides whether the next real move should cross
the protected simulator AI boundary.

- Design critic: the evidence points toward policy sequencing, not raw
  Spore/Wrath values. A narrow protected AI probe is likely needed.
- Measurement critic: no protected AI probe until a joined decision-regret
  report proves a repeated actionable defect, separating no-good-offer cases
  from affordable-focus-skipped cases.
- Implementation critic: safe H77 write surface is analyzer/tests/docs/traces
  only. Stop before `godot/sim/**`, Druid card data, generated DB, or broad
  gameplay claims.

Decision: implement the joined analyzer first. Use its gate to decide whether
to request protected AI approval.

## Implemented Diagnostic

Added `--druid-path-lag-audit` to `scripts/analyze_ai_trace.py`.

The report joins `path_lag_hold` events to existing trace fields:

- round, path, current phase, focus list, held best card, held-card score.
- focus-card visibility and affordability inside the same offer list.
- HP/gold/shop level from `round_start`.
- same-round reroll/buy counts.
- same-round battle result, HP after battle, and survivor margin.
- run-phase conversion bucket from the H76 diagnostic.

The diagnostic separates holds into:

- `affordable_focus_available`
- `focus_offered_unaffordable`
- `no_focus_offer_druid_body_held`
- `no_focus_offer_high_value_neutral_held`
- `no_focus_offer_neutral_held`
- `no_focus_offer_high_value_offtheme_held`
- `no_focus_offer_low_value_held`

It prints an approval gate:

- `GO_PROTECTED_PROBE_FOCUS_SCORE_ORDERING`
- `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`
- `NO_GO_NO_PATH_LAG_HOLDS`
- `NO_GO_NEEDS_STRONGER_DECISION_ATTRIBUTION`

When combined with `--druid-compare-baseline`, it also prints candidate vs
baseline hold deltas and repeats whether a protected AI policy probe is
justified. This is not gameplay evidence by itself; it is an approval gate for
the next behavioral probe.

## Real-Trace Validation

Command:

```bash
python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces
```

H75 path-lag audit:

- Scope: R8-R12.
- Holds: `265` from `51/60` runs.
- Focus offered during holds: `5`.
- Affordable focus during holds: `1`.
- No-focus-offer holds: `260/265` (`98.1%`).
- Actionable no-focus loss runs: `36`.
- Average holds per loss: `4.1`.
- Max same-round holds: `8`.
- Average hold HP start/after: `21.6/21.6`.
- Loss enemy survivors after held rounds: `13.9`.
- Categories:
  - `no_focus_offer_druid_body_held`: `104`
  - `no_focus_offer_neutral_held`: `77`
  - `no_focus_offer_high_value_neutral_held`: `76`
  - `focus_offered_unaffordable`: `4`
  - `no_focus_offer_low_value_held`: `3`
  - `affordable_focus_available`: `1`
- By round: R9 `132`, R10 `76`, R11 `37`, R12 `20`.
- By phase: payoff `245`, capstone `20`.
- Top held cards: `ne_mutant_adapt 28`, `dr_grace 26`,
  `ne_ancient_catalyst 22`, `dr_resonance 20`, `dr_cradle 15`,
  `dr_prune 13`.
- Approval gate: `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.
- Next signal: protected AI probe recommended. The current hold policy mostly
  fires when no focus card is visible, so the narrow next probe should test a
  stabilizer-buy fallback before more card-value tuning.

Path split:

- `druid_garden`: `113` holds, `27` losses, `98.2%` no-focus,
  `18` actionable no-focus loss runs, gate
  `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.
- `druid_world_tree`: `151` holds, `21` losses, `98.0%` no-focus,
  `17` actionable no-focus loss runs, same gate.

H75 vs H71 path-lag comparison:

- Holds: `255 -> 265` (`+10`).
- Hold runs: `50 -> 51` (`+1`).
- No-focus hold rate: `98.4% -> 98.1%`.
- Actionable no-focus loss runs: `37 -> 36`.
- Affordable focus holds: `1 -> 1`.
- Candidate approval gate: `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.

Interpretation: this is baseline behavior, not an H75-only regression. The
decision defect appears stable across H71/H75 and is not caused by the rejected
Spore/Wrath values.

## Verification

- PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (19 tests).
- PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (22 tests).
- PASS `python3 scripts/analyze_ai_trace.py --help`.
- PASS real-trace H75-vs-H71 path-lag audit command.
- PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py docs/tools/self-play-observer.md`.

## Decision

Adopt the analyzer-only H77 diagnostic.

Do not claim gameplay is fixed. Do not edit protected simulator AI without
explicit approval. The evidence now justifies requesting a narrow protected
probe.

## Resume Note

Recommended H78, pending explicit approval for `godot/sim/**`: implement a
temporary soft-Druid path-lag policy probe.

Narrow hypothesis:

- When `soft_druid` is in payoff/capstone path lag and no focus card is visible
  in the shop, do not always hard-hold. Allow selected stabilizing purchases,
  especially high-value Druid bodies and high-value neutral stabilizers, while
  preserving current/next focus priority when focus is visible.

Candidate gate:

- Same-seed H71/H75-style 60-run screen must improve clears and/or average HP
  without increasing H74 reject signals.
- H76 `--druid-run-phase` must reduce `active_too_late` or no-focus losses.
- H77 `--druid-path-lag-audit` must reduce no-focus hold pressure without
  increasing `affordable_focus_available`.
- Confirm any passing same-seed result on a disjoint seed before adoption.
