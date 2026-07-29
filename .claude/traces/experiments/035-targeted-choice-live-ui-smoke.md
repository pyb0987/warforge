# Episode 035: Targeted-choice live UI smoke

## Context

H38 promoted the live UI observer into a command-line JSON report. Its carry-over
identified the next missing gate: targeted choices. The report could prove
run-start, merge reward, and one no-target boss reward, but it did not yet prove
that a reward can open a visible target overlay, expose eligible targets, apply
the selected effect, clean up, and resume BUILD.

## Advisory Multi-Review

Mode: `FALLBACK_NONINDEPENDENT`, advisory only.

Decision: choose the first targeted smoke path.

Critics:

- Gameplay/UX critic: prefer a simple targeted reward that proves the player
  interaction. Recommended R4 `r4_1` over R12 `r12_1` because `r4_1` has one
  target and a concrete visible effect.
- Observability critic: add a small public target-overlay contract instead of
  driving private signal state. Recommended exposing selectable field indices,
  instruction/detail text, preview text, and a public `select_field_index()`.
- Scope/false-green critic: do not claim random reward-offer coverage from a
  forced targeted choice. Recommended recording `forced_choice=true`, keeping
  the existing random no-target boss reward path, and making the report fail
  closed.

Decision: use R4 `r4_1` for H39 and carry R12 two-step/screenshot evidence to
later slices.

## Change

Added a public selection contract to `TargetSelectOverlay`:

- `is_active()`;
- `get_selectable_field_indices()`;
- `select_field_index(field_idx)`;
- `get_instruction_text()`;
- `get_detail_text()`.

Extended `LiveUiProbe`:

- adds `target_select` modal ownership;
- snapshots selectable field indices;
- snapshots target instruction/detail/preview text;
- can select a target through the overlay's public path.

Extended the live UI smoke report with a deterministic targeted boss reward
event:

- seeds a selectable ★1 card and an ineligible ★3 card;
- forces the real `BossRewardPopup` to show `r4_1`;
- selects the reward through the popup;
- verifies `TargetSelectOverlay` owns the UI;
- verifies only field `0` is selectable;
- verifies preview text includes both `★1 -> ★2` and `MAX ★3`;
- selects field `0` through the overlay public method;
- verifies the card evolves to ★2, Terazin increases by at least the reward's
  +4 grant after settlement, and R5 BUILD is clean.

Added the same path to `test_game_manager_live_smoke.gd`.

Updated `docs/tools/live-ui-smoke-report.md` to document the targeted reward
coverage.

## Findings While Implementing

The first H39 report attempt exposed a report false-green risk: `ok` defaulted
to `true`, so a runtime script error could leave a partial JSON artifact marked
successful. The reporter now defaults to `ok=false` and only sets `ok=true`
after all scripted events finish and the final snapshot is written.

The targeted reward Terazin assertion also needed to account for settlement
income. The report now records `terazin_delta_after_settlement` and requires it
to be at least the reward grant amount rather than exactly `+4`.

## Verification

Report:

```text
PASS godot --headless --log-file /private/tmp/warforge_h39_live_ui_report_v4.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h39_live_ui_report_v4.json --commander=gambler --talisman=flint
  ok=true; steps=12; targeted_boss_reward.selected_reward=r4_1; selectable_field_indices=[0]; target_star_before=1; target_star_after=2; final=BUILD R5; final.has_modal=false

PASS python3 -c 'import json; p="/private/tmp/warforge_h39_live_ui_report_v4.json"; d=json.load(open(p)); assert d["ok"] is True; ev=d["events"]["targeted_boss_reward"]; assert ev["selected_reward"] == "r4_1"; assert ev["selectable_field_indices"] == [0]; assert ev["target_star_before"] == 1 and ev["target_star_after"] == 2; assert ev["terazin_delta_after_settlement"] >= 4; assert d["final"]["phase"] == "BUILD" and d["final"]["has_modal"] is False; print("ok", len(d["steps"]), ev["terazin_delta_after_settlement"])'
  ok 12 6
```

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h39_live_smoke_v2.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  10/10; 276 asserts

PASS godot --headless --log-file /private/tmp/warforge_h39_build_phase_upgrade_shop.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit
  12/12

PASS godot --headless --log-file /private/tmp/warforge_h39_game_manager_logic.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit
  36/36

PASS godot --headless --log-file /private/tmp/warforge_h39_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  2/2

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h39_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1222/1222; 7825 asserts
```

## Decision

Keep the H39 change.

Reason:

- It closes the largest remaining semantic UI gap in the live smoke report:
  targeted choice ownership and cleanup.
- It adds a reusable public target-overlay driver for future smoke tests.
- It improves report reliability by failing closed by default.
- Focused and full verification pass.

Carry-over:

- H40 should add optional screenshot artifacts for selected report steps so
  visual overlap/layout regressions can be inspected alongside semantic JSON.
- Later targeted slices can cover R12 `r12_1` two-step targeting if boss reward
  targeting itself regresses or becomes a high-risk area again.
