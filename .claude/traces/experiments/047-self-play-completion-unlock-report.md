# Episode 047: Self-play completion/unlock report

Date: 2026-07-27

## Context

H50 made boss reward comparison text observable in the live UI workflow. The
remaining choice was whether to immediately polish that reward popup or step
back and inspect the whole loop again. The user had also previously raised a
manual-play concern that one run unlocked many items at once.

This slice did not change gameplay values. No card data, reward effects,
economy numbers, enemy curve, or difficulty presets were changed.

## Advisory Multi-Review

Three independent critics reviewed the next-slice choice:

- Player UX critic: score 8, recommended a post-choice `LAST REWARD` recap so
  players can see what changed after a boss reward selection.
- Engineering/Testability critic: score 8, recommended a narrow boss reward
  comparison layout cleanup guarded by the H50 rendered-text/screenshot checks.
- Completion/Roadmap critic: score 8, challenged the local UI carry-over and
  recommended hardening the self-play completion observer first, because H43-H50
  had already spent many slices on live UI readability/observability.

Decision: implement H51 as a self-play completion/unlock report workflow. Keep
boss reward layout and reward-result recap as plausible player-facing follow-up
slices, but let the next code change be driven by full-loop evidence.

## Change

`SelfPlayObserverLogic.summarize()` now adds:

- `schema: warforge-self-play-observer/v1`;
- `completion`, including clear rate, final/loss round distributions, and
  R4/R8/R12 boss milestone reach vs reward-application counts;
- `unlock_projection`, a partial meta-progression projection from available
  headless result fields.

The unlock projection reports clear rewards, field-unit thresholds, upgrade
event thresholds, win streak, growth events, star-2 final deck counts, and
unit-advantage wins. Card-sale unlocks are marked unobservable because current
headless results do not export sold-card counts. Threshold constants are kept in
the observer to avoid preloading `MetaProgress` from a standalone `-s` tool; a
focused GUT test compares those constants to `MetaProgress` so drift is caught.

Added `scripts/summarize_self_play_report.py`, which validates the JSON shape
and produces a compact Markdown completion summary. The Markdown includes
overall clear rate, strategy split, boss milestone reach/reward counts, unlock
projection metrics, largest projected-unlock runs, and alerts.

`docs/tools/self-play-observer.md` now documents the new JSON sections and the
Markdown summary command.

## Representative Self-Play Evidence

Command:

```text
godot --headless --log-file /private/tmp/warforge_h51_selfplay_matrix_v2.log --path godot/ -s tools/self_play_observer.gd -- --runs=2 --strategies=adaptive,soft_steampunk,soft_druid,soft_predator,soft_military --difficulty=1 --commander=gambler --talisman=flint --seed=2026072751 --include-results=true --quiet-progress=true --out=/private/tmp/warforge_h51_selfplay_matrix_v2.json
```

Result:

```text
PASS self-play matrix
  schema=warforge-self-play-observer/v1
  total_runs=10
  clears=6/10
  largest_projected_unlock_count=9
  runs_with_projected_unlocks=9
  alerts=possible_unlock_burst, partial_unlock_projection
  boss milestones: R4 10 reached / 10 rewarded; R8 10 / 7; R12 8 / 5
```

Markdown summary:

```text
PASS python3 scripts/summarize_self_play_report.py --report /private/tmp/warforge_h51_selfplay_matrix_v2.json --out /private/tmp/warforge_h51_selfplay_matrix_summary_v2.md
  Overall: 6/10 clears (60.0%), avg rounds 13.30, avg final HP 12.80.
  soft_druid: 0/2 clears, avg rounds 10, avg boss rewards 1.50.
  Largest projected run: soft_steampunk projected 9 unlocks on a D1 clear.
```

Log guard:

```text
PASS rg -n "SCRIPT ERROR|Compile Error|ERROR:" /private/tmp/warforge_h51_selfplay_matrix_v2.log
  no matches
```

## Verification

Focused observer GUT:

```text
PASS godot --headless --log-file /private/tmp/warforge_h51_self_play_observer_gut_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_self_play_observer.gd -glog=1 -gexit
  7/7 passed, 48 asserts
```

Python summary/lint tests:

```text
PASS python3 -m unittest scripts.tests.test_summarize_self_play_report scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_summarize_live_ui_report
  30 tests OK

PASS python3 -m py_compile scripts/summarize_self_play_report.py scripts/summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Formatting:

```text
PASS rg -n "[ \t]+$" godot/tools/self_play_observer_logic.gd godot/tests/test_self_play_observer.gd scripts/summarize_self_play_report.py scripts/tests/test_summarize_self_play_report.py docs/tools/self-play-observer.md
  no matches

PASS git diff --check
```

Full suite:

```text
PASS godot --headless --log-file /private/tmp/warforge_h51_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1239/1239 passed, 7997 asserts
```

## Decision

Keep H51. The workflow now turns autonomous self-play into a completion-gap
artifact instead of only a raw simulator dump.

## Carry-Over

The next evidence-backed slice is unlock pacing. The H51 matrix projects large
single-run unlock bursts even after the earlier stricter thresholds. Before
changing thresholds, run a focused design/implementation review on whether the
projection is exact enough or whether headless/live run stats need stronger
source fields, especially for card-sale unlocks and final-snapshot lower-bound
metrics.

Secondary carry-over: boss reward choice layout and post-choice reward-result
recap remain useful UI slices, but they are behind the unlock pacing audit.
