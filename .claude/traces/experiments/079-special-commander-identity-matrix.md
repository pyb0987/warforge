# Episode 079: Special-Commander Identity Matrix

Date: 2026-07-29
Owner: Codex
Plan item: H83

## Purpose

Use the H82 live UI identity matrix to probe beyond the curated default rows and
close the next unprotected completion gap. The expanded special-commander probe
showed that the reporter, not the core game loop, was too rigid around valid
commander-specific upgrade modals.

## Probe

Expanded matrix command:

```bash
python3 scripts/run_live_ui_identity_matrix.py \
  --output-dir=/private/tmp/warforge_h82_expanded_identity_probe \
  --out=/private/tmp/warforge_h82_expanded_identity_probe/matrix.json \
  --summary-out=/private/tmp/warforge_h82_expanded_identity_probe/matrix.md \
  --identity=breeder=breeder:cracked_egg \
  --identity=collector=collector:glass_eye \
  --identity=strategist=strategist:war_drum \
  --identity=smith=smith:rusty_wrench \
  --identity=raider=raider:mercury_drop
```

Initial result: 3/5 passed.

- Smith opened a legitimate start `upgrade_choice` modal before the generic
  chain-feedback step.
- Raider's scripted terminal victory waited on the 3-win free-upgrade flow,
  because the smoke had already accumulated two Raider wins earlier in the
  scripted path.

## Changes

- `live_ui_smoke_report.gd` now resolves optional commander free-upgrade modals
  through the visible upgrade-choice modal and target overlay, then records
  `events.commander_free_upgrade`.
- The terminal unlock smoke now resets Raider's local `win_count` just before
  the artificial final battle and records
  `events.commander_scripted_adjustments.raider_terminal_win_count_reset`.
  This avoids a test-only dead wait while keeping terminal unlock recap evidence
  intact. Raider's real 3-win upgrade attachment remains covered by focused
  commander/build tests.
- `summarize_live_ui_report.py` now validates optional commander-free-upgrade
  events and includes them in the playtest summary when present.
- `docs/tools/live-ui-smoke-report.md` documents the expanded special-commander
  matrix command and optional event fields.

## Verification

- PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py scripts/run_live_ui_identity_matrix.py scripts/tests/test_run_live_ui_identity_matrix.py`.
- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_run_live_ui_identity_matrix -q`
  (38 tests).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  (13/13).
- PASS expanded identity matrix:

```bash
python3 scripts/run_live_ui_identity_matrix.py \
  --output-dir=/private/tmp/warforge_h83_expanded_identity_matrix_final \
  --out=/private/tmp/warforge_h83_expanded_identity_matrix_final/matrix.json \
  --summary-out=/private/tmp/warforge_h83_expanded_identity_matrix_final/matrix.md \
  --timeout-sec=90 \
  --identity=breeder=breeder:cracked_egg \
  --identity=collector=collector:glass_eye \
  --identity=strategist=strategist:war_drum \
  --identity=smith=smith:rusty_wrench \
  --identity=raider=raider:mercury_drop
```

Result:

- `Verdict: PASS`
- `Passing identities: 5/5`
- PASS `breeder`: 양성가 + 깨진 알
- PASS `collector`: 수집가 + 유리 눈
- PASS `strategist`: 전략가 + 전쟁 북
- PASS `smith`: 단조사 + 녹슨 렌치
- PASS `raider`: 약탈자 + 수은 방울

No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
difficulty values, or Godot runtime/player-facing scene files were changed for
H83.

## Next

- Unprotected: add a named expanded preset to the matrix CLI if this probe
  should become routine, or add focused live evidence for Raider's real 3-win
  upgrade timing.
- Protected: H78, the Druid path-lag stabilizer AI probe, still requires
  explicit approval before editing `godot/sim/**`.
