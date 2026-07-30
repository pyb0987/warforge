# Episode 080: Raider Real 3-Win Live Evidence

Date: 2026-07-29
Owner: Codex
Plan item: H84

## Purpose

H83 fixed the live UI report so the expanded identity matrix could pass for
special commanders. It also added a harness-only Raider terminal-win adjustment
to avoid a test dead wait. H84 closes the evidence gap created by that
adjustment: Raider reports now separately prove the real 3-win upgrade reward
through visible UI.

## Changes

- `live_ui_smoke_report.gd` now runs a Raider-only focused reward event:
  - clear and seed a valid field target;
  - set Raider `win_count` to 2;
  - trigger a non-boss winning battle;
  - drive the visible common-upgrade choice;
  - drive the visible field target overlay;
  - assert one upgrade attached, win count reset to 0, and the run returned to
    modal-free BUILD R3.
- The event is recorded as `events.raider_win_streak_reward`.
- `summarize_live_ui_report.py` now requires that event for Raider reports,
  validates upgrade count, target, instruction text, win-counter reset, and
  modal-free BUILD return, then prints a readable line in the summary.
- `docs/tools/live-ui-smoke-report.md` documents the Raider-only event.

No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
difficulty values, or player-facing runtime scenes were changed.

## Verification

- PASS direct Raider report:

```bash
/usr/bin/env HOME=/private/tmp/warforge_h84_raider_home \
  godot --headless \
  --log-file /private/tmp/warforge_h84_raider_report.log \
  --path godot/ \
  res://tools/live_ui_smoke_report.tscn -- \
  --out=/private/tmp/warforge_h84_raider_report.json \
  --commander=raider \
  --talisman=mercury_drop \
  --unlock-selected=true
```

- PASS direct Raider summary:

```bash
python3 scripts/summarize_live_ui_report.py \
  --report /private/tmp/warforge_h84_raider_report.json \
  --out /private/tmp/warforge_h84_raider_summary.md
```

Key summary evidence:

- `Verdict: PASS`
- `Report OK: yes`
- `Commander free upgrade flow resolved: raider_win_streak_upgrade: C4 -> field 0`
- `Raider 3-win reward proved live: C4 -> field 0, upgrades 0->1, win count 0, BUILD R3`

- PASS expanded identity matrix:

```bash
python3 scripts/run_live_ui_identity_matrix.py \
  --output-dir=/private/tmp/warforge_h84_expanded_identity_matrix \
  --out=/private/tmp/warforge_h84_expanded_identity_matrix/matrix.json \
  --summary-out=/private/tmp/warforge_h84_expanded_identity_matrix/matrix.md \
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

- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_run_live_ui_identity_matrix -q`
  (41 tests).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  (13/13).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit`
  (17/17).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit`
  (37/37).
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit`
  (37/37).
- PASS `git diff --check`.

## Next

- Unprotected: make the expanded identity matrix a named preset if it should be
  routine, or move to the next player-facing completion gap.
- Protected: H78, the Druid path-lag stabilizer AI probe, still requires
  explicit approval before editing `godot/sim/**`.
