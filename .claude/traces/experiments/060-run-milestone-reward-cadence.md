# H64 - Run Milestone Reward Cadence

Date: 2026-07-29
Status: ADOPTED

## Objective

Make the early run loop explain why the player should continue after the first
fight. H63 made the first battle less opaque by previewing enemy pressure; H64
adds reward cadence context by naming the next boss reward or final boss
milestone on the BUILD surface and after settlement.

## Decision

Advisory multi-review split between another battle-start clarity slice and a
broader run-cadence clarity slice. I chose the frame-challenge recommendation:
after H60-H63, the larger player-facing gap was not "what happens if I press
BUILD COMPLETE?" but "why am I doing more rounds?".

Deferred:
- A richer battle-start status panel during BATTLE.
- Exact enemy scouting or prediction.
- A full roadmap/progression rail beyond compact milestone copy.

## Implementation

- `godot/scripts/build/build_phase.gd`
  - Added public milestone accessors for observer/tests:
    `get_run_milestone_text()` and `get_round_label_text()`.
  - Expanded the round HUD label to include the next milestone:
    `Round 1/15 · R4 boss reward in 4 fights`.
  - Added short and full milestone formatters that point to R4/R8/R12 boss
    rewards and R15 final boss.
  - Extended the post-settlement next-step recap with the same milestone:
    `Next: R2 BUILD · R4 boss reward in 3 fights`.

- `godot/scenes/build/build_phase.tscn`
  - Updated default RoundLabel and SettlementNextLabel text so scene defaults
    reflect the new cadence language.

- `godot/tools/live_ui_probe.gd`
  - Exported `run_milestone` text, round-label text, visibility, and rect.
  - Added the round-label rect to layout exports.

- `godot/tools/live_ui_smoke_report.gd`
  - Captures milestone evidence at initial BUILD, post-settlement BUILD, and
    post-unlock BUILD entry.
  - Fails if the milestone is missing, non-visible, or no longer references the
    boss-reward cadence.

- `scripts/summarize_live_ui_report.py`
  - Validates run milestone evidence and includes it in the playtest summary.
  - Requires settlement recap text to retain boss-reward cadence.

- Tests updated:
  - `godot/tests/test_build_phase_tutorial.gd`
  - `godot/tests/test_game_manager_live_smoke.gd`
  - `scripts/tests/test_summarize_live_ui_report.py`
  - `docs/tools/live-ui-smoke-report.md`

## Verification

PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
- 26 tests passed.

PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit`
- 17/17 passed, 76 asserts.

PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
- 12/12 passed, 725 asserts.

PASS headless live UI smoke report with `--commander=gambler --talisman=flint`.
- Initial BUILD: `Goal: R4 boss reward in 4 fights`.
- Post-settlement BUILD: `Goal: R4 boss reward in 3 fights`.
- Settlement recap: `Next: R2 BUILD · R4 boss reward in 3 fights`.

PASS `python3 scripts/summarize_live_ui_report.py --report=/private/tmp/warforge_live_ui_smoke_h64.json --out=/private/tmp/warforge_live_ui_smoke_h64_summary.md`
- Verdict PASS.
- Summary includes run milestone cadence.

PASS `python3 scripts/lint_card_spawn.py`

PASS `python3 -m unittest discover -s scripts/tests`
- 107 tests passed.

PASS `git diff --check`

PASS exact merge-marker scan:
`rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
- No matches.

PASS full GUT in isolated Godot profile:
`HOME=/private/tmp/warforge_godot_home_h64full godot --headless --log-file /private/tmp/warforge_full_gut_h64full.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
- 57 scripts.
- 1264/1264 tests passed.
- 8526 asserts.

Note: a default-profile full GUT rerun first failed because Godot could not
write/reset `user://` profile files under the desktop default profile path. A
focused `test_meta_progress.gd` pass and the full isolated-profile pass show
this was an environment/profile-path issue, not an H64 regression.

## Outcome

ADOPTED. The run now advertises its next reward milestone from BUILD entry
through first settlement, giving the player a simple reason to keep playing
without adding a larger roadmap UI yet.
