# Experiment 077 - Run Progression Rail

Date: 2026-07-29
Status: ADOPTED

## Purpose

Continue progress toward a complete playable game while H78 remains gated by
explicit approval for protected `godot/sim/**` edits.

H64 made the BUILD HUD name the next boss reward or final-boss milestone, but
the player still did not get a compact full-run map. The next player-facing gap
was run orientation: a player should be able to see the current round in the
R1-R15 arc and understand that R4/R8/R12 are reward milestones before the R15
final boss.

## Advisory Multi-Review

Verdict: ADVISORY PASS for an unprotected player-facing H81 rail.

- Player-completion critic: preferred a real BUILD HUD progression rail over
  another report-only proof, because the rail directly helps players steer a run.
- Observability critic: preferred a live UI identity matrix runner as the next
  reporting step; kept as follow-up.
- Scope-safety critic: warned against touching protected simulator policy or
  growing the dirty worktree; H81 stayed in unprotected UI/report/docs files.

## Change

- `BuildPhase` round HUD now renders a second compact rail line:
  `R1 NOW | rewards R4 next, R8, R12 | R15 final`.
- The rail derives reward milestones from `Enums.BOSS_ROUNDS` and marks past
  milestones `done`, the current milestone `now`, and the next future milestone
  `next`.
- `LiveUiProbe` exposes `progress_rail_text` with existing run milestone
  details.
- `live_ui_smoke_report.gd` records and validates the rail at BUILD entry,
  after first settlement, and post-unlock BUILD entry.
- `summarize_live_ui_report.py` validates the rail against rendered round label
  text, includes it in the Markdown playtest summary, and also reports whether
  `--unlock-selected=true` preunlocked the selected identity for an isolated
  report profile.
- `docs/tools/live-ui-smoke-report.md` documents both `--unlock-selected=true`
  and the new progression rail evidence.

No protected simulator AI files, gameplay balance values, card YAML, generated
card DB, or difficulty values were changed.

## Verification

- PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py`.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
  (30 tests).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit`
  (17/17).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  (13/13).
- PASS `/usr/bin/env HOME=/private/tmp/warforge_godot_home_h81_golden_report_final godot --headless --log-file /private/tmp/warforge_h81_golden_die_report_final.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h81_golden_die_report_final.json --commander=gambler --talisman=golden_die --unlock-selected=true`.
- PASS `python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h81_golden_die_report_final.json --out /private/tmp/warforge_h81_golden_die_summary_final.md`.
- PASS Golden Die summary evidence:
  - `Verdict: PASS`.
  - `Report OK: yes`.
  - `Selected identity setup: unlock-selected profile (talismans 6)`.
  - `Run progression rail rendered: R1 NOW | rewards R4 next, R8, R12 | R15 final.`
  - `Boss reward popup title: 보스 보상 선택 (1개 선택 / 6개 후보).`
- PASS full GUT in isolated Godot profile:
  `/usr/bin/env HOME=/private/tmp/warforge_godot_home_h81_full_gut_final godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
  (57 scripts, 1275/1275 tests, 8807 asserts).
- PASS `git diff --check`.

The command-line live UI report still prints the pre-existing Godot ObjectDB /
resource exit warning after completion, but the JSON report and Markdown
summary both passed, and the full GUT run exited cleanly.

## Next

Two plausible next steps remain:

- Unprotected: add a small live UI identity matrix runner that uses
  `--unlock-selected=true` across curated commander/talisman identities and
  emits a compact pass/fail table.
- Protected: H78, the Druid path-lag stabilizer AI probe, still requires
  explicit approval before editing `godot/sim/**`.
