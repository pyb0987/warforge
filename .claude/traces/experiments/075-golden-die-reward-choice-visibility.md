# Experiment 075 - Golden Die Reward Choice Visibility

Date: 2026-07-29
Status: ADOPTED

## Purpose

Keep moving on game-completion hardening while H78 remains gated by explicit
approval for protected `godot/sim/**` edits.

The player-facing concern was that talisman effects should be visible when they
matter. Golden Die already changed boss reward choice count through
`Talisman.get_boss_reward_choices()`, but the live popup did not state how many
choices were being shown and the live smoke suite did not prove the six-choice
path through the real run UI.

Design reference: `docs/design/talismans.md` says Golden Die applies at
R4/R8/R12 boss rewards and changes the display from 4 to 6 choices.

## Change

- `BossRewardPopup.show_choices()` now renders the candidate count in the title:
  `보스 보상 선택 (1개 선택 / N개 후보)`.
- `test_game_manager_live_smoke.gd` now unlocks Golden Die in an isolated smoke
  profile, selects it through the real run-start talisman popup, wins R4, and
  asserts that the real boss reward popup exposes six choice IDs, six rendered
  summaries, and a title containing `6개 후보`.
- `live_ui_smoke_report.gd` now records boss reward `open_title` and
  `open_choice_count`.
- `summarize_live_ui_report.py` validates that the recorded choice count matches
  rendered summaries and includes the popup title in the Markdown playtest
  summary.

No protected simulator AI files, gameplay balance values, card YAML, generated
card DB, or difficulty values were changed.

## Verification

- PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py`.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
  (28 tests).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit`
  (3/3).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  (13/13).
- PASS `/usr/bin/env HOME=/private/tmp/warforge_godot_home_h79_live_report godot --headless --log-file /private/tmp/warforge_h79_live_ui_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h79_live_ui_report.json --commander=gambler --talisman=flint`.
- PASS `python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h79_live_ui_report.json --out /private/tmp/warforge_h79_live_ui_summary.md`.
- PASS summary evidence:
  - `Verdict: PASS`.
  - `Report OK: yes`.
  - `Boss reward popup title: 보스 보상 선택 (1개 선택 / 4개 후보).`
- PASS full GUT in isolated Godot profile:
  `/usr/bin/env HOME=/private/tmp/warforge_godot_home_h79_full_gut godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
  (57 scripts, 1274/1274 tests, 8709 asserts).

The command-line live UI report still prints the pre-existing Godot ObjectDB /
resource exit warning after completion, but the report itself was OK and the
full GUT run exited cleanly with all tests passing.

## Next

H78 remains the most direct gameplay-completion blocker: a protected Druid
path-lag stabilizer AI probe. It still requires explicit approval before
editing `godot/sim/**`.
