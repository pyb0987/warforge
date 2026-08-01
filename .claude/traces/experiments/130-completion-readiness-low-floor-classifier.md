# H128 Completion Readiness Low-Floor Classifier

Date: 2026-08-01
Base commit: `3de34748c301cf99ad7c9a2720abec9566bbf87d`

## Trigger

A fresh 490-run all-core D1 scout returned `completion_readiness.status=watch`
with only `unlock_burst_pressure`, while the same report showed soft-Druid at
6/70 clears (8.6%) and average R10.8. That is a false-green routing result for
the M1 strategy viability floor because unlock burst is currently only a watch
item and soft-Druid remains the blocking lane.

Scout artifacts:
- Report: `/private/tmp/warforge_h130_current_scout.json`
- Summary: `/private/tmp/warforge_h130_current_scout_summary.md`
- Traces: `/private/tmp/warforge_h130_current_scout_traces`

## Multi-Review

Two independent critics agreed the classifier, not the summary renderer, was
the failure point. Both recommended an absolute low-strategy clear-rate floor
instead of relative underperformance versus the overall clear rate. One critic
explicitly warned not to classify soft-Steampunk at 24/70 (34.3%) as the same
high-severity blocker.

## Change

Updated `godot/tools/self_play_observer_logic.gd` so `_weak_strategy_rows`
flags a sampled strategy as high-risk when it has:
- zero clears on at least 3 runs,
- average rounds below 8.0 on at least 3 runs, or
- fewer than 20% clears on at least 10 runs.

Updated evidence text to include the clear percentage, added regression tests
for a nonzero 15% strategy lane and the strict 20% boundary, and documented the
threshold in the observer guide.

## Verification

PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit`
- 11/11 passed, including the new low-nonzero and 20% boundary cases.

PASS `git diff --check`

PASS `python3 scripts/lint_card_spawn.py`

PASS `python3 -m unittest scripts.tests.test_lint_card_spawn`
- 10 tests OK.

PASS `python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h130_current_scout.json --out /private/tmp/warforge_h130_current_scout_summary_after_classifier.md`

PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
- 1301/1301 passed.

## Result

The existing scout JSON remains an old generated artifact and still contains
the pre-fix `watch` readiness value. Future observer runs from this code path
will surface soft-Druid-like nonzero low-clear lanes as `weak_strategy_floor`
and route the next slice back to strategy-floor diagnosis.

No gameplay, Druid runtime, simulator, YAML, generated DB, economy, difficulty,
or unlock-threshold values changed.
