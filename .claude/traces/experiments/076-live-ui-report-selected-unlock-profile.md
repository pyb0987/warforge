# Experiment 076 - Live UI Report Selected Unlock Profile

Date: 2026-07-29
Status: ADOPTED

## Purpose

Finish the current observability run slice before pausing. H79 made Golden Die
reward choice visibility testable inside GUT, but the standalone live UI report
could not reliably select locked run identities from a fresh reset profile
without manual meta-save preparation.

The goal was to make command-line self-play reports cover locked commander or
talisman paths intentionally, while keeping unlock recap validation honest. The
report should not assume a fixed first-run unlock list after the setup hook
changes the already-unlocked state.

## Change

- Added `--unlock-selected=true` to `live_ui_smoke_report.gd`.
- When used with `--reset-meta`, the report unlocks only the requested selected
  commander/talisman before saving the isolated test profile. Selection still
  goes through the real commander/talisman popup flow.
- Report metadata records whether this setup hook ran and which selected
  commanders/talismans were preunlocked.
- Unlock recap events now include the raw unlock list and raw count.
- Unlock recap assertions are derived from the actual raw list:
  - shown rows are the first three unlocks;
  - overflow count is `max(0, raw_count - 3)`;
  - overflow text is required only when overflow exists;
  - the first overflow row must not leak into the visible recap.
- `summarize_live_ui_report.py` mirrors the same dynamic validation instead of
  assuming the original fixed first-run 12-unlock shape.

No protected simulator AI files, gameplay balance values, card YAML, generated
card DB, or difficulty values were changed.

## Verification

- PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py`.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
  (29 tests).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  (13/13).
- PASS `/usr/bin/env HOME=/private/tmp/warforge_godot_home_h80_golden_report godot --headless --log-file /private/tmp/warforge_h80_golden_die_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h80_golden_die_report.json --commander=gambler --talisman=golden_die --unlock-selected=true`.
- PASS `python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h80_golden_die_report.json --out /private/tmp/warforge_h80_golden_die_summary.md`.
- PASS Golden Die summary evidence:
  - `Verdict: PASS`.
  - `Report OK: yes`.
  - `Talisman: 황금 주사위`.
  - `Boss reward popup title: 보스 보상 선택 (1개 선택 / 6개 후보).`
  - `Boss reward choices rendered` contains six rendered choices.

The command-line live UI report still prints the pre-existing Godot ObjectDB /
resource exit warning after completion, but the JSON report and Markdown
summary both passed, and H79's full GUT run remains the latest full-suite clean
baseline at 1274/1274.

## Decision

ADOPT. The self-play reporting workflow can now exercise locked talisman paths
directly, which makes future player-facing reports less dependent on manual
profile setup and better aligned with the user's observed Golden Die issue.

## Pause Point

Per user request, stop after this current run. The next likely completion
candidate remains H78, the protected Druid path-lag stabilizer probe, but it
still requires explicit approval before editing `godot/sim/**`.
