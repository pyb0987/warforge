# Episode 046: Boss reward rendered-choice observability

Date: 2026-07-27

## Context

H49 closed the battle-result -> settlement -> next-BUILD comprehension loop.
The next player-facing gap was boss reward comparison: the live UI smoke report
could prove that reward IDs were present and actionable, but it could not yet
prove what reward text the player actually saw before selection.

This slice targeted observability only. It did not change reward pools, reward
effects, card data, combat math, economy values, difficulty tuning, or selection
policy.

## Change

`BossRewardPopup` now exposes rendered choice summaries from the same live UI
nodes the player sees. Each summary records:

- reward id and visible choice index;
- rendered name, type label, description, and joined text;
- whether the reward requires a target;
- the global panel rectangle.

The popup assigns stable node names to its generated card controls so the
observer can read the actual labels instead of reconstructing data from reward
IDs.

`LiveUiProbe.snapshot()` exports `boss_reward` details and the popup layout
rect. The command-line live UI smoke report records normal R4 boss reward
choice summaries, the selected summary, and a deterministic targeted `r4_1`
choice summary before target selection opens.

The screenshot lint and playtest summary now validate/report the rendered boss
reward comparison surface. The lint requires visible names, types, descriptions,
target flags, and nonzero panel rects. It also distinguishes the normal boss
reward frame, which must include at least one immediate reward option, from the
forced targeted reward frame, which must include exactly one target-dependent
reward.

## Verification

Focused popup GUT:

```text
PASS godot --headless --log-file /private/tmp/warforge_h50_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  3/3 passed, 23 asserts
```

Python summary/lint tests:

```text
PASS python3 -m unittest scripts.tests.test_lint_live_ui_screenshots scripts.tests.test_summarize_live_ui_report
  28 tests OK

PASS python3 -m py_compile scripts/summarize_live_ui_report.py scripts/lint_live_ui_screenshots.py
```

Live-scene smoke:

```text
PASS godot --headless --log-file /private/tmp/warforge_h50_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  12/12 passed, 345 asserts
```

Headless semantic report and summary:

```text
PASS godot --headless --log-file /private/tmp/warforge_h50_headless_report_v2.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h50_headless_report_v2.json --commander=gambler --talisman=flint
  ok=true; screenshot_status=disabled; boss_reward_open exposes 4 rendered summaries; targeted_boss_reward_open exposes 1 targeted summary

PASS python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h50_headless_report_v2.json --out /private/tmp/warforge_h50_headless_summary.md
```

GUI screenshot report, lint, summary, and visual inspection:

```text
PASS godot --log-file /private/tmp/warforge_h50_gui_screenshot_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h50_gui_screenshot_report.json --screenshot-dir=/private/tmp/warforge_h50_gui_shots --commander=gambler --talisman=flint
  ok=true; screenshot_status=enabled; screenshots=16

PASS python3 scripts/lint_live_ui_screenshots.py --report /private/tmp/warforge_h50_gui_screenshot_report.json
  PASS live UI screenshot lint: 16 screenshots, 1280x720

PASS python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h50_gui_screenshot_report.json --lint-screenshots --out /private/tmp/warforge_h50_gui_summary.md

PASS visual inspection /private/tmp/warforge_h50_gui_shots/011-boss_reward_open.png
  Four boss reward cards are visible with readable names, type labels, and
  descriptions.

PASS visual inspection /private/tmp/warforge_h50_gui_shots/013-targeted_boss_reward_open.png
  The forced targeted reward card is visible and describes the target-dependent
  star evolve plus Terazin reward before target selection opens.
```

Formatting and full suite:

```text
PASS git diff --check

PASS godot --headless --log-file /private/tmp/warforge_h50_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1236/1236 passed, 7963 asserts
```

## Decision

Keep H50. Boss reward comparison is now visible to both the player and the
automated playtest workflow before any reward is selected.

## Carry-Over

The next plausible player-facing slice is to improve the boss reward comparison
layout itself: make immediate, permanent, direct, and targeted choices easier to
scan at a glance, now that the report can prove what text and target markers
actually render.
