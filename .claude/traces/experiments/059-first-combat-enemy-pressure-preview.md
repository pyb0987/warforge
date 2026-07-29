# H63: First-Combat Enemy Pressure Preview

## Objective

Improve the first BUILD screen so the player can see what kind of enemy pressure
they are about to commit into before pressing `BUILD COMPLETE`.

## Multi-Review Decision

Three advisory critics converged on a small first-combat preview, but the
engineering critic flagged the main failure mode: an exact pre-confirm scout
could call or duplicate `EnemyDB.generate()`, advance `_battle_rng`, or display
an enemy army that later differs from combat.

Adopted shape:

- show a compact pressure range in the existing BUILD readiness panel;
- derive it from pure round/preset profile data;
- mark the data as non-exact;
- do not roll or cache actual enemy composition in H63.

Deferred:

- exact rolled enemy scouting needs a pending-enemy cache or separate enemy RNG
  stream mirrored in live play and headless simulation.

## Implementation

- Added `EnemyDB.pressure_profile(round, genome, difficulty)`, a pure helper
  that summarizes all enemy presets for the round as count, ATK, and HP ranges
  without taking a `RandomNumberGenerator`.
- Extended the BUILD readiness panel with an `ENEMY:` line such as:
  `ENEMY: R1 4-9기 · ATK 26-31 HP 222-335`.
- Exposed `get_enemy_pressure_preview_text()` and
  `get_enemy_pressure_preview_data()` from `BuildPhase`.
- Added `enemy_pressure_preview` to `LiveUiProbe` snapshots and live UI smoke
  report events.
- Updated the playtest summary to validate and report the preview as a required
  before-commit cue.
- Documented the JSON/report contract in `docs/tools/live-ui-smoke-report.md`.

## Verification

PASS:

- `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 25 tests.
- `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_db.gd -glog=1 -gexit`
  - 21 tests, 59 asserts.
- `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit`
  - 16 tests, 68 asserts.
- `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12 tests, 652 asserts.
- Headless live UI smoke report:
  `/private/tmp/warforge_live_ui_smoke_h63.json`.
- Live UI playtest summary:
  `/private/tmp/warforge_live_ui_smoke_h63_summary.md`
  - Verdict PASS.
  - Includes `Enemy pressure preview rendered before commit`.
- `python3 scripts/lint_card_spawn.py`.
- `python3 -m unittest discover -s scripts/tests`
  - 106 tests.
- `git diff --check`.
- `rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
  - no matches.
- Full GUT:
  - 57 scripts.
  - 1263 tests.
  - 8445 asserts.

## Notes

The preview intentionally does not name a single enemy archetype, because the
actual archetype is still rolled by battle generation. The UI copy and report
data should keep that distinction clear until exact scouting is designed.
