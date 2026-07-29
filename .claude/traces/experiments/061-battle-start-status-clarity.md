# H65 - Battle-Start Status Clarity

Date: 2026-07-29
Status: ADOPTED

## Objective

Close the H64 deferred battle-start clarity gap. The player already sees
commander/talisman identity, first BUILD readiness, first-shop role cues, enemy
pressure preview, and run milestone cadence; the remaining first-combat handoff
was that the actual BATTLE screen still felt like an opaque animation instead
of confirming the generated matchup.

## Decision

Advisory multi-review produced:

- UX/product critic: choose battle-start status clarity. The BATTLE handoff is
  the first moment that should prove the player's board is really fighting.
- Engineering-risk critic: choose the same slice tightly. The false-green risk
  was that reports could pass from cached or synthetic aftermath data while the
  real BATTLE label remained vague or invisible.
- Frame-challenge critic: prefer refreshing current completion/self-play
  evidence before more local UI polish.

I adopted the first option because two reviewers converged on a narrow,
player-visible gap with a concrete false-green guard. The completion evidence
refresh remains the next larger gate when autonomous work resumes.

Deferred:

- Exact scouting or pre-battle enemy prediction.
- A rich combat causality/log panel.
- A full run roadmap rail.
- A current completion/self-play evidence refresh.

## Implementation

- `godot/scripts/battle/battle_phase.gd`
  - `start_battle()` now accepts battle context and records round/start counts.
  - The status label now renders live text like
    `BATTLE R1 | Start 9A vs 6E | Now 9A vs 6E | Tick 0 | 1x`.
  - Added `get_status_details()` so tests and reports can verify rendered
    status data from the live `BattlePhase`.
  - Added cleanup for stale status text and engine disposal.

- `godot/scripts/game/game_manager.gd`
  - Passes round, ally start count, and enemy start count into `BattlePhase`
    when the generated armies are handed off to combat.

- `godot/tools/live_ui_probe.gd`
  - Exports `battle_status` text, visibility, rect, and structured data from
    the live battle phase.

- `godot/tools/live_ui_smoke_report.gd`
  - Captures a real `battle_status_live` BATTLE snapshot after chain feedback
    and before synthetic battle aftermath.
  - Fails if the status is hidden, missing dimensions, not in BATTLE phase, or
    does not include round/start/current count evidence.

- `scripts/summarize_live_ui_report.py`
  - Validates `events.battle_status.battle_status_live` against the rendered
    report step and includes the battle-start line in the playtest summary.

- Tests and docs updated:
  - `godot/tests/test_game_manager_live_smoke.gd`
  - `scripts/tests/test_summarize_live_ui_report.py`
  - `scripts/lint_live_ui_screenshots.py`
  - `docs/tools/live-ui-smoke-report.md`

## Verification

PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
- 27 tests passed.

PASS `python3 -m unittest scripts.tests.test_lint_live_ui_screenshots`
- 18 tests passed.

PASS `python3 -m py_compile scripts/summarize_live_ui_report.py`

PASS focused live smoke:
`HOME=/private/tmp/warforge_godot_home_h65_live2 godot --headless --log-file /private/tmp/warforge_live_smoke_h65_focus2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
- 12/12 passed.
- 736 asserts.

PASS headless live UI smoke report:
`HOME=/private/tmp/warforge_godot_home_h65_report godot --headless --log-file /private/tmp/warforge_live_ui_smoke_h65.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_live_ui_smoke_h65.json --commander=gambler --talisman=flint`
- Captured `battle_status_live`.
- Rendered text:
  `BATTLE R1 | Start 9A vs 6E | Now 9A vs 6E | Tick 0 | 1x`.

PASS `python3 scripts/summarize_live_ui_report.py --report=/private/tmp/warforge_live_ui_smoke_h65.json --out=/private/tmp/warforge_live_ui_smoke_h65_summary.md`
- Verdict PASS.
- Summary includes battle-start status evidence.

PASS `python3 scripts/lint_card_spawn.py`

PASS `python3 -m unittest discover -s scripts/tests`
- 108 tests passed.

PASS `git diff --check`

PASS exact merge-marker scan:
`rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
- No matches.

PASS full GUT in isolated Godot profile:
`HOME=/private/tmp/warforge_godot_home_h65_full godot --headless --log-file /private/tmp/warforge_full_gut_h65.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
- 57 scripts.
- 1264/1264 tests passed.
- 8537 asserts.

## Outcome

ADOPTED. The first real BATTLE frame now confirms the round and actual generated
matchup counts to the player, and the live UI report proves this on the real
battle screen before it moves into scripted aftermath.

The user asked to finish only this current run and then pause. Do not start H66
until they explicitly resume autonomous development.
